#! /usr/bin/python
import MySQLdb
import psycopg2
import psycopg2.extras
import bs4
import re
import json
import sys
import SocketServer
import lxml.html
from urllib2 import urlopen
from pattern.vector import count, KNN, stem, PORTER, words, Document

conn = psycopg2.connect("dbname='nlpdatabase' user='jpyle' password='xxxsecretxxx' host='192.168.200.35'")

knn = None
pages = None
urlalias = None
revurlalias = None

def setup():
    global pages
    global urlalias
    global revurlalias
    global knn
    pages = dict()
    urlalias = dict()
    revurlalias = dict()
    knn = KNN()
    db = MySQLdb.connect(host="192.168.200.26",
                         user="root",
                         passwd="xxxsecretxxx",
                         db="pla")
    cur = db.cursor()
    cur.execute("select source, alias from url_alias")
    for row in cur.fetchall():
        urlalias[row[1]] = row[0]
        revurlalias[row[0]] = row[1]
    cur.execute("select tid, name, description, vid from taxonomy_term_data;")
    for row in cur.fetchall():
        url = 'taxonomy/term/' + str(row[0])
        pages[url] = row[1]
        if url in revurlalias:
            pages[revurlalias[url]] = row[1]
            url = revurlalias[url]
        if row[3] == 3:
            soup = bs4.BeautifulSoup(row[2])
            the_text = re.sub(r'[\n\r]+', r'  ', soup.get_text(' ')).lower()
            knn.train(Document(the_text, stemmer=PORTER), url)
            knn.train(Document(row[1].lower()), url)
    cur.execute("select a.tid, c.body_value, d.title from taxonomy_term_data as a inner join field_data_field_practice_areas as b on (a.tid=b.field_practice_areas_tid and b.entity_type='node' and b.bundle != 'professionals' and b.deleted=0) inner join field_data_body as c on (b.entity_id=c.entity_id and b.entity_type=c.entity_type) inner join node as d on (c.entity_id=d.nid);")
    for row in cur.fetchall():
        url = 'taxonomy/term/' + str(row[0])
        if url in revurlalias:
            url = revurlalias[url]
        soup = bs4.BeautifulSoup(row[1])
        the_text = re.sub(r'[\n\r]+', r'  ', soup.get_text(' ')).lower()
        knn.train(Document(the_text, stemmer=PORTER), url)
        knn.train(Document(row[2].lower()), url)
    cur.execute("select nid, title from node where status=1;")
    for row in cur.fetchall():
        url = 'node/' + str(row[0])
        pages[url] = row[1]
        if url in revurlalias:
            pages[revurlalias[url]] = row[1]
    db.close()
    pgcur = conn.cursor()
    pgcur.execute("select query, target from website_queries where target is not null group by query, target")
    for row in pgcur.fetchall():
        words = re.split(r'[\n\r,;]+ *', row[1])
        for word in words:
            print("training on " + row[0].lower() + " for " + word)
            knn.train(Document(row[0].lower()), word)
    conn.commit()
    pgcur.close()

def store_query(query, suggestion):
    pgcur = conn.cursor()
    pgcur.execute("insert into website_queries (query, orig_sug) values (%s, %s);", ( query, suggestion ))
    conn.commit()
    pgcur.close()
    
def evaluate_query(query):
    probs = dict()
    for key, value in knn.classify(Document(query), discrete=False).iteritems():
        probs[key] = value
    if not len(probs):
        probs[knn.classify(Document(query))] = 1.0
    seen = set()
    probs = map(lambda x: fixurl(x, seen), sorted(probs, key=probs.get, reverse=True))
    probs = [prob for prob in probs if prob is not None]
    return probs

def fixurl(x, seen):
    if x in pages:
        description = pages[x]
    elif x in urlalias and urlalias[x] in pages:
        description = pages[urlalias[x]]
    else:
        try:
            description = fixup(lxml.html.parse(urlopen(x)).find(".//title").text)
            if not description:
                description = x
        except Exception as the_err:
            sys.stderr.write(str(the_err) + "\n")
            description = x
        pages[x] = description
    if re.search(r'^http', x):
        url = str(x)
    else:
        url = '/' + str(x)
    if description in seen:
        return None
    seen.add(description)
    return '<a href="' + url + '">' + description + '</a>'

def fixup(x):
    x = re.sub(r'^ +', r'', x)
    x = re.sub(r' +$', r'', x)
    x = re.sub(r'[\(\[\]\)\n\r\t`#%$*]', r'', x)
    return x

#print 'https://philalegal.org/taxonomy/term/' + str(knn.classify(Document('I want to sue the IRS.')))

class MyTCPHandler(SocketServer.BaseRequestHandler):
    def handle(self):
        self.data = self.request.recv(1024).strip()
        print "{} wrote:".format(self.client_address[0])
        print self.data
        query = self.data
        if query.startswith("___RESET___"):
            setup()
            self.request.sendall('{"message": "Thank you"}')
        else:
            orig_query = query
            query = query.lower()
            response = json.dumps(evaluate_query(query))
            store_query(orig_query, response)
            self.request.sendall(response)

if __name__ == "__main__":
    setup()
    HOST, PORT = "localhost", 6693
    SocketServer.ThreadingTCPServer.allow_reuse_address = True
    server = SocketServer.TCPServer((HOST, PORT), MyTCPHandler)
    server.serve_forever()
