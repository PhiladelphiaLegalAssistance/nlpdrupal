#! /usr/bin/perl -w

use strict;
use warnings;
use Carp;
use CGI;
use DBI;
use JSON;
use Date::Manip;
use IO::Socket::INET;

my $q = CGI->new();

print $q->header();

my $connect = DBI->connect("DBI:mysql:database=pla;host=192.168.200.26", "root", "xxxsecretxxx");

my $dref = DBI->connect('dbi:Pg:dbname=nlpdatabase', '', '', {AutoCommit => 1}) or croak DBI->errstr;

my $update = $dref->prepare("update website_queries set target=? where indexno=?") or croak $dref->errstr;

my $delete = $dref->prepare("delete from website_queries where indexno=?") or croak $dref->errstr;

my $do_update = 0;
foreach my $param ($q->param()){
  if ($param =~ m/^target(.*)/){
    my $target = $1;
    if ($q->param($param) =~ m/[A-Za-z]/){
      if ($q->param($param) =~ m/ignore/i){
        $delete->execute($target);
      }
      else{
        $update->execute(mytrim($q->param($param)), $target);
        $do_update = 1;
      }
    }
  }
}
if ($do_update){
  my $sock = new IO::Socket::INET (
				   PeerHost => 'localhost',
				   PeerPort => '6693',
				   Proto => 'tcp',
				  ) or die "ERROR in Socket Creation : $!\n";
  print $sock "___RESET___\n";
  my $response = <$sock>;
  $sock->close();
}

my %external_sites;
{
  my $targets = $dref->prepare("select target from website_queries where target like '%http%'") or croak $dref->errstr;
  $targets->execute() or croak $targets->errstr;
  while (my $d = $targets->fetchrow_hashref()){
    foreach my $url (split(/[;,] */, $d->{target})){
      if ($url =~ m/^http/){
	$external_sites{$url}++;
      }
    }
  }
}

my $query = $dref->prepare("select datetime, indexno, query, orig_sug from website_queries where target is null order by datetime") or croak $dref->errstr;

$query->execute() or croak $query->errstr;

print <<'EOF';
<!DOCTYPE html>
<html lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" />
  <link rel="stylesheet" type="text/css" href="/html/mycss.css" />
  <title>Classify legal problem descriptions</title>
</head>
<body>
<div class="container">
<form method="POST">
EOF

print "<h1>Classify legal problem descriptions</h1>\n";

my $show = 0;

while (my $d = $query->fetchrow_hashref()){
  $show = 1;
  print "<div>\n";
  print "<p><b>" . UnixDate(ParseDate($d->{datetime}), '%B %e, %Y, %i:%M %p') . "</b></p>\n";
  print "<p>" . $d->{query} . "</p>\n";
  print $q->textfield(
		      -name => 'target' . $d->{indexno},
		      -id => 'target' . $d->{indexno},
		      -default => '',
		      -override => 1,
		      -size => 60,
		     );
  if ($d->{orig_sug}){
    print "<p>" . join(" ", map {fixup($_, 'target' . $d->{indexno})} @{decode_json($d->{orig_sug})}) . " " . fixup("<a href=\"/ignore\">Ignore</a>", 'target' . $d->{indexno}) . "</p>\n";
  }
  print "</div>\n";
}

if($show){
  print "<div>\n";
  print $q->submit(-name => 'Update',
		   -value => 'Update');
  print "</div>\n";
}
else{
  print "<p>No new web site queries.</p>\n";
}

print $q->end_form;

my %url_alias;

my $myquery = $connect->prepare("select source, alias from url_alias") or croak $connect->errstr;
$myquery->execute();
while (my @results = $myquery->fetchrow_array()) {
  $url_alias{$results[0]} = $results[1];
}

my %pages;
$myquery = $connect->prepare("select a.tid, a.vid, a.name, b.name as taxname FROM taxonomy_term_data as a inner join taxonomy_vocabulary as b on (a.vid=b.vid)") or croak $connect->errstr;
$myquery->execute();
while (my @d = $myquery->fetchrow_array()) {
  $pages{$d[3]}->{$d[2]} = 'taxonomy/term/' . $d[0];
}

$myquery = $connect->prepare("select a.nid, a.title, b.name as content_type FROM node as a inner join node_type as b on (a.type=b.type) where a.status = 1") or croak $connect->errstr;
$myquery->execute();
while (my @d = $myquery->fetchrow_array()) {
  $pages{$d[2]}->{$d[1]} = 'node/' . $d[0];
}

print "\n<h2>External URLs</h2>\n";

print "\n<table class=\"table table-bordered\">\n";
print "  <thead><tr><th>URL</th></tr></thead>\n";
print "  <tbody>\n";
foreach my $url (sort {$external_sites{$b} <=> $external_sites{$a}} keys %external_sites){
  print '    <tr><td><span>' . $url . '</span> <a target="_blank" href="' . $url . '"><span class="glyphicon glyphicon-new-window" aria-hidden="true"></span></a></td></tr>' . "\n";
}
print "  </tbody>\n";
print "</table>\n";

print "\n<h2>PLA URLs</h2>\n";

print "\n<table class=\"table table-bordered\">\n";
foreach my $category (sort keys %pages){
  print "  <thead><tr><th colspan=\"2\"><b>" . $category . "</b></th></tr></thead>\n";
  print "  <tbody>\n";
  foreach my $title (sort keys %{$pages{$category}}){
    print "    <tr><td>" . $title . "</td><td>" . ($url_alias{$pages{$category}->{$title}} // $pages{$category}->{$title})  . "</td></tr>\n"
  }
  print "  </tbody>\n";
}
print "</table>\n";

print "</div>\n";
print '<script type="text/javascript" src="https://code.jquery.com/jquery-3.1.1.min.js"></script>' . "\n";
print <<'EOF';
<script>
  $(".mysug").each(function(){
    $(this).attr('href', '#' + $(this).data('href'));
    $(this).on('click', function(e){
      var target = $(this).data('target');
      if ($(this).data('href') != 'ignore' && $("#" + target).val()){
        $("#" + target).val($("#" + target).val() + '; ' + $(this).data('href'));
      }
      else{
        $("#" + target).val($(this).data('href'));
      }
      e.preventDefault();
      return false;
    });
  });
</script>
EOF
print $q->end_html;
exit;

sub mytrim {
  my $text = shift;
  $text =~ s/^ +| +$//g;
  return $text;
}

sub fixup {
  my $text = shift;
  my $id = shift;
  $text =~ s/href\="\//href="/g;
  $text =~ s/href\=/href="#" data-href=/g;
  my $class = 'primary';
  if ($text =~ m/"ignore"/){
    $class = 'warning';
  }
  $text =~ s/\<a /<a data-target="$id" class="btn btn-$class btn-sm mysug" /g;
  return $text;
}
