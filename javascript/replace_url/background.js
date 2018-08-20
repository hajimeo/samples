// "persistent": true, is required for onBeforeRequest
// Also https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(replaceUrl, {
    //urls: ['https://*/*'],  // for debug
    urls: ['https://*.visual.force.com/*'], //'https://*.salesforce.com/console*', 'https://customers.atscale.com/50*'
    types: ["main_frame"]
});

function replaceUrl(details) {
    // Assuming ID starts with 50
    // protocol + (hostname/path_to_id=) + (caseId), so that the index of groups is 2
    var caseId_regex = new RegExp("^https://(.+\.salesforce.com/console#%2F|.+\.visual\.force\.com/apex/Case_Lightning.*[?&]id=)(50[^\?&]+)");

    console.log("Request: TabID = " + details.tabId + " | url = " + details.url);
    chrome.tabs.get(details.tabId, function (tab) {
        if (chrome.runtime.lastError) {
            console.log(chrome.runtime.lastError.message);
            return;
        }
        if (!tab) return;
        var match = caseId_regex.exec(details.url);
        console.log("match 1 = " + match);

        if (match && match.length > 1) {
            //var new_url = "https://na63.salesforce.com/console#%2F" + match[1];
            //var new_url = "https://customers.atscale.com/" + match[2];
            var new_url = "https://customers.atscale.com/s/case/" + match[2] + "/detail";
            console.log("New URL = " + new_url);
            chrome.tabs.update(tab.id, {url: new_url});
        }
    });
}
