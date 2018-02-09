javascript:var cls="_hltr_";
var highlight = function (searchWordsString, textContainerNode) {
    /* TODO: remove highlights which has cls */
    var searchWords = searchWordsString.split(' ');
    for (var i in searchWords) {
        var regex = new RegExp(">([^<]*)?\\b("+searchWords[i]+")\\b([^>]*)?<", "ig");
        highlightTextNodes(textContainerNode, regex, i);
    }
};
var highlightTextNodes = function (element, regex, i) {
    /* TODO: up to 3 colors */
    var tmp_elm_html = element.innerHTML;
    var colors = ['background-color:#fcfa9f', 'background-color:#9ff6fc', 'background-color:#b0fc9f'];
    var i2 = i % colors.length;
    console.log("DEBUG: i="+i+ " i2="+i2+" style="+colors[i2]+" regex="+regex+" innerHTML.len="+tmp_elm_html.length);
    element.innerHTML = tmp_elm_html.replace(regex, '>$1<span style="' + colors[i2] + '" class="'+cls+'">$2</span>$3<');
};
var selected = "" + (window.getSelection ? window.getSelection() : document.getSelection ? document.getSelection() : document.selection.createRange().text);
var sw = prompt("Highlighting words:", selected);
highlight(sw, document.body);
void 1;