javascript:w = window;
d = document;
s = "" + (w.getSelection ? w.getSelection() : d.getSelection ? d.getSelection() : d.selection.createRange().text);
q = prompt("search word", s);
if (q != null) {
    (function (s) {
        q = encodeURIComponent(s);
        w.open("https://chatgpt.com/?q=" + q, "t_chatgpt");
        w.open("https://www.phind.com/search?q=" + q + "&ignoreSearchResults=false&allowMultiSearch=false", "t_phind");
        w.open("https://www.perplexity.ai/search?q=" + q, "t_perplex");
    })(q)
}
void 1;

w.open("http://localhost:48080/?q=" + q + "&models=gemma2:latest", "t_openwebui");
/* TODO: add Gemini (@gemini), AWS Q and Github Copilot (probably not possible though) */
w.open("https://gemini.google.com/app", "t_gemini");
w.open("https://github.com/search?l=&q=" + q, "t_github");
w.open("https://docs.aws.amazon.com/search/doc-search.html?searchPath=documentation&searchQuery=" + q, "t_awsdoc");
