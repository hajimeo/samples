javascript:w = window;
d = document;
s = "" + (w.getSelection ? w.getSelection() : d.getSelection ? d.getSelection() : d.selection.createRange().text);
q = prompt("search word", s);
if (q != null) {
    (function (s) {
        q = encodeURIComponent(s);
        w.open("https://issues.apache.org/jira/issues/?jql=text ~ \"" + s.replace(/(")/g, '\\$1') + "\" ORDER BY created DESC", "t_apa_jira");
        w.open("https://cwiki.apache.org/confluence/dosearchsite.action?queryString=" + q, "t_apa_wiki");
        w.open("https://hadoop-and-hdp.blogspot.com.au/search?q=" + q, "t_blog");
        w.open("http://search.osakos.com/index.php?query=" + q + "&rows=50&submit=Search&indexes%5B%5D=hadoop&indexes%5B%5D=hajime&indexes%5B%5D=public&adv=1", "t_hajigle");
        w.open("https://www.google.com/search?q=" + q + "%20site%3Ahortonworks.com", "t_ggl");
        w.open("https://github.com/search?l=&q=" + q + "+org%3Ahortonworks&ref=advsearch&type=Code&utf8=%E2%9C%93", "t_github");
        w.open("https://drive.google.com/drive/search?ltmpl=drive&q=" + q, "t_drive");
        w.open("https://mail.google.com/mail/u/0/#search/" + q, "t_gmail");
        w.open("https://myactivity.google.com/myactivity?q=" + q, "t_myactivity");
    })(q)
}
void 1;

//w.open("https://issues.apache.org/jira/secure/QuickSearch.jspa?searchString="+q, "t_apa_jira");
//w.open("https://issues.apache.org/jira/secure/Dashboard.jspa", "t_apa_jira").location="https://issues.apache.org/jira/secure/QuickSearch.jspa?jql=text%20~%20\"" + q + "\"\"%20ORDER%20BY%20created%20DESC";
//w.open("https://stackoverflow.com/search?q=" + q, "t_sto");
//w.open("http://search-hadoop.com/?q=" + q + "", "t_hdp");

javascript:w = window;
d = document;
s = "" + (w.getSelection ? w.getSelection() : d.getSelection ? d.getSelection() : d.selection.createRange().text);
q = prompt("search word", s);
if (q != null) {
    (function (s) {
        q = encodeURIComponent(s);
        w.open("https://hortonworks.my.salesforce.com/_ui/search/ui/UnifiedSearchResults?asPhrase=0&str=" + q, "t_sf");
        w.open("https://hortonworks.jira.com/secure/QuickSearch.jspa?jql=project in (EAR%2C BUG) AND text ~ \"" + s.replace(/(")/g, '\\$1') + "\" ORDER BY created DESC", "t_hw_jira");
        w.open("http://172.26.104.144/source/search?defs=&refs=&path=&hist=&type=&q=" + q, "t_grok");
        w.open("https://hipchat.hortonworks.com/search?q=" + q + "&t=all&a=Search", "t_hipchat");
        w.open("https://hortonworks.app.box.com/folder/0/search?query=" + q + "&types=&updatedTime=&owners=&itemSize=&updatedTimeFrom=&updatedTimeTo=&tags=", "t_box");
        w.open("https://hwxmonarch.atlassian.net/secure/QuickSearch.jspa?searchString=" + q, "t_hw_jira2");
        w.open("https://drive.google.com/drive/u/1/search?q=" + q, "t_drive2");
        w.open("https://wiki.hortonworks.com/dosearchsite.action?queryString=" + q + "&where=conf_all", "t_wiki");
    })(q)
}
void 1;