javascript:w = window;
d = document;
s = "" + (w.getSelection ? w.getSelection() : d.getSelection ? d.getSelection() : d.selection.createRange().text);
q = prompt("search word", s);
if (q != null) {
    (function (s) {
        q = encodeURIComponent(s);
        /* TODO: add Gemini (@gemini), AWS Q and Github Copilot (probably not possible though) */
        w.open("https://gemini.google.com/app", "t_gemini");
        w.open("https://github.com/search?l=&q=" + q, "t_github");
        /*w.open("https://docs.aws.amazon.com/search/doc-search.html?searchPath=documentation&searchQuery=" + q, "t_awsdoc");*/
        w.open("https://www.perplexity.ai/search?q=" + q, "t_perplex");
        w.open("https://www.phind.com/search?q=" + q + "&ignoreSearchResults=false&allowMultiSearch=false", "t_phind");
    })(q)
}
void 1;