/**
 * Based on https://www.eriwen.com/javascript/highlight-search-results-with-js/
 */
function highlight(searchWordsString, textContainerNode) {
    var searchWords = searchWordsString.split(' ');
    for (var i in searchWords) {
        var regex = new RegExp(">([^<]*)?(" + searchWords[i] + ")([^>]*)?<", "ig");
        highlightTextNodes(textContainerNode, regex, i);
    }
}

function highlightTextNodes(element, regex, i) {
    // TODO: up to 3 colors
    var tmp_elm_html = element.innerHTML;
    var colors = ['background-color:#fcfa9f', 'background-color:#9ff6fc', 'background-color:#b0fc9f'];
    var i2 = i % colors.length;
    console.log("DEBUG: i="+i+ " i2="+i2+" style="+colors[i2]+" regex="+regex+" innerHTML.len="+tmp_elm_html.length);
    element.innerHTML = tmp_elm_html.replace(regex, '>$1<span style="' + colors[i2] + '">$2</span>$3<');
}