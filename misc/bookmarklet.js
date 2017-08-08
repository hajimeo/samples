javascript:w=window;d=document;
s=""+(w.getSelection?w.getSelection():d.getSelection?d.getSelection():d.selection.createRange().text);
q=prompt("search word",s);
if(q!=null){
    (function(s){
        q=encodeURIComponent(s);
        w.open("https://issues.apache.org/jira/secure/QuickSearch.jspa?searchString="+q, "t_apa_jira");
        w.open("https://github.com/search?l=&q="+q+"+user%3Ahortonworks&ref=advsearch&type=Code&utf8=%E2%9C%93", "t_github");
        w.open("https://stackoverflow.com/search?q="+q, "t_sto");
        w.open("http://search-hadoop.com/?q="+q+"", "t_hdp");
        w.open("https://www.google.com/search?q="+q+"%20site%3Ahortonworks.com", "t_ggl");
        w.open("https://drive.google.com/drive/search?ltmpl=drive&q="+q, "t_drive");
        w.open("https://mail.google.com/mail/u/0/#search/"+q, "t_gmail");
        w.open("https://hadoop-and-hdp.blogspot.com.au/search?q="+q, "t_blog");
        w.open("http://search.osakos.com/index.php?query="+q+"&rows=50&submit=Search&indexes%5B%5D=hadoop&indexes%5B%5D=hajime&indexes%5B%5D=public&adv=1", "t_hajigle");
        w.open("https://myactivity.google.com/myactivity?q="+q, "t_myactivity");
    })(q)}
void 1;