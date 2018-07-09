// "persistent": true, is required for onBeforeRequest
// Also https://developer.chrome.com/apps/match_patterns for url match pattern
chrome.webRequest.onBeforeRequest.addListener(replaceUrl, {
    urls: ['https://na63.salesforce.com/50*', 'https://customers.atscale.com/50*'],
    types: ["main_frame"]
});

function replaceUrl(details) {
    // Assuming ID starts with 50
    //var url_regex = new RegExp('https://(na63\.salesforce\.com|customers\..+.com)/50*');
    //if (!url_regex.test(details.url)) return;
    var caseId_regex = new RegExp("^http.+\.com/(50[^\?&]+)");
    console.log("Request: TabID = " + details.tabId + " | url = " + details.url);

    chrome.tabs.get(details.tabId, function (tab) {
        if (chrome.runtime.lastError) {
            console.log(chrome.runtime.lastError.message);
            return;
        }
        if (!tab) return;
        var match = caseId_regex.exec(details.url);
        if (match && match.length > 1) {
            var new_url = "https://na63.salesforce.com/console#%" + match[1];
            console.log("New URL = " + new_url);
            chrome.tabs.update(tab.id, {url: new_url});
        }
    });
}
