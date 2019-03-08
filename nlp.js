function receive_freetext(response, x){
  var links = JSON.parse(response);
  var arrayLength = links.length;
  document.getElementById('userfreetext').innerHTML = document.getElementById('freetextquery').value
  var linklist = document.getElementById('freetextlinks');
  linklist.innerHTML = '';
  for (var i = 0; i < arrayLength; i++) {
    var new_li = document.createElement('li');
    new_li.innerHTML = links[i];
    linklist.appendChild(new_li);   
  }
  document.getElementById('freetextresponsesection').style.display = 'block';
  document.getElementById('freetextblock').style.display = 'none';
  jQuery("#freetextend").scrollintoview();
}

function submit_freetext(){
  var el = document.getElementById('freetextquery');
  thetext = el.value;
  if (thetext){
    var img = document.createElement('img');
    img.src = "/html/loader.gif";
    img.style.position = 'absolute';
    img.style.top = '0px';
    img.style.right = '50%';
    document.getElementById('freetextblock').appendChild(img);
    document.getElementById('freetextsubmit').disabled = true;
    document.getElementById('freetextquery').disabled = true;
    if (thetext && thetext !== ""){
      ajax("/proxycgi/website_client.pl", receive_freetext, 'q=' + encodeURI(thetext));
    }
  }
}

function freetext_init(event){
  var el = document.getElementById('freetextsubmit');
  if (el){
    if (el.addEventListener){
      el.addEventListener("click", submit_freetext, false);
    }
    else {
      el.attachEvent('onclick', submit_freetext);
    } 
  }
}

if(window.attachEvent) {
    window.attachEvent('onload', freetext_init);
} else {
    if(window.onload) {
        var curronload = window.onload;
        var newonload = function(evt) {
            curronload(evt);
            freetext_init(evt);
        };
        window.onload = newonload;
    } else {
        window.onload = freetext_init;
    }
}

function ajax(url, callback, data, x) {
	try {
		x = new(this.XMLHttpRequest || ActiveXObject)('MSXML2.XMLHTTP.3.0');
		x.open(data ? 'POST' : 'GET', url, 1);
		x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
		x.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
		x.onreadystatechange = function () {
			x.readyState > 3 && callback && callback(x.responseText, x);
		};
		x.send(data)
	} catch (e) {
		window.console && console.log(e);
	}
};
