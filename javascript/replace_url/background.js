// "persistent": true, is required for onBeforeRequest
// Also https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(replaceUrl, {
    //urls: ['https://*/*'],  // for debug
    urls: ['https://*.lightning.force.com/lightning/*', 'https://*.visual.force.com/*', 'https://customers.atscale.com/*'], //'https://*.salesforce.com/console*'
    types: ["main_frame"]
}, ["blocking"]);

function replaceUrl(details) {
    console.log("=== Start 'replaceUrl' ================================");
    // Assuming ID starts with 50
    // protocol + (hostname/path_to_id=) + (caseId), so that the index of groups is 2
    var caseId_regex = new RegExp("^https://(.+\.lightning\.force\.com/lightning/r/Case/|.+\.visual\.force\.com/apex/Case_Lightning.*[?&]id=|customers\.atscale\.com/s/case/)(50[^\?&/]+)");
    var tab_regex = new RegExp("^https://(.+\.lightning\.force\.com/lightning/r/Case/)");

    console.log("Request: details.tabId = " + details.tabId + " | url = " + details.url);

    chrome.tabs.query({currentWindow: true}, function (tabs) {
        var tab_id = null;
        tabs.forEach(function (tab) {
            if (tab_id === null && tab.id != details.tabId) {
                if (tab_regex.exec(tab.url)) {
                    tab_id = tab.id;
                    console.log('Already opened tab ID: ', tab_id);
                    console.log('and tab URL: ', tab.url);
                }
            }
        });

        if (tab_id) {
            console.log('Closing : ', details.tabId);
            chrome.tabs.remove(details.tabId, function () {
            });
        } else {
            console.log('Returning : ', details.url);
            return {redirectUrl: details.url}
        }

        var match = caseId_regex.exec(details.url);
        console.log("matches = " + match);

        if (match && match.length > 1) {
            var new_url = "https://atscale2ndorg.lightning.force.com/lightning/r/Case/" + match[2] + "/view";
            //var new_url = "https://na63.salesforce.com/console#%2F" + match[2];
            //var new_url = "https://customers.atscale.com/" + match[2];
            //var new_url = "https://customers.atscale.com/s/case/" + match[2] + "/detail";
            console.log("New URL = " + new_url);
            chrome.tabs.update(tab_id, {url: new_url});
        }
    });
}