javascript:var w = window;
var l = document.links;
for (i = 0; i < l.length; i++) {
    if (l[i].text == "View") {
        if (confirm("Download "+l[i].title+"?")) {
            w.open(l[i].href, "dl_tmp"+i);
        }
    }
}
void 1;