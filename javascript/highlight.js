/**
 * Based on https://www.eriwen.com/javascript/highlight-search-results-with-js/
 */
function highlight(searchWordsString) {
    // Starting node, parent to all nodes you want to search
    var textContainerNode = document.getElementsByTagName("body");

    // Split search terms on '|' and iterate over resulting array
    var searchWords = searchWordsString.split(' ');
    for (var i in searchWords) 	{
        // The regex is the secret, it prevents text within tag declarations to be affected
        var regex = new RegExp(">([^<]*)?("+searchWords[i]+")([^>]*)?<","ig");
        highlightTextNodes(textContainerNode, regex, i);
        // Add to info-string
    }

    // Insert as very first child in searched node
    textContainerNode.insertBefore(searchTermDiv, textContainerNode.childNodes[0]);
}

function highlightTextNodes(element, regex, termid) {
    var tempinnerHTML = element.innerHTML;
    // TODO: up to 3 colors
    var colors = ['background-color: #161633', 'background-color: #331616', 'background-color: #163316'];
    var i = termid % colors.length;
    // Do regex replace
    // Inject span with class of 'highlighted termX' for google style highlighting
    element.innerHTML = tempinnerHTML.replace(regex,'>$1<span style="'+colors[i]+'">$2</span>$3<');
}

selected = "" + (window.getSelection ? window.getSelection() : document.getSelection ? document.getSelection() : document.selection.createRange().text);
highlight(prompt("Find:", selected));