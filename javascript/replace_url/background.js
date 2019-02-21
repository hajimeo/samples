// "persistent": true is required for onBeforeRequest
// Check https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(replaceUrl, {
    //urls: ['https://*/*'],  // for debug
    urls: ['https://*.lightning.force.com/lightning/*', 'https://*.visual.force.com/*', 'https://customers.atscale.com/s/case/*'], //'https://*.salesforce.com/console*'
    types: ["main_frame"]
}, ["blocking"]);

// Assuming ID starts with 50, and protocol + (hostname/path_to_id=) + (caseId), so that the index of groups is 2
var caseId_regex = new RegExp("^https://(.+\.lightning\.force\.com/lightning/r/Case/|.+\.visual\.force\.com/apex/Case_Lightning.*[?&]id=|customers\.atscale\.com/s/case/)(50[^\?&/]+)");
var tab_regex = new RegExp("^https://(.+\.lightning\.force\.com/lightning/[ro]/Case/)");
var ignore_regex = new RegExp("^https://.+\.lightning\.force\.com/lightning/(_classic/)");

function replaceUrl(details) {
    console.log("=== Start 'replaceUrl' ================================");
    console.log("Request: details.tabId = " + details.tabId + " | url = " + details.url);

    console.log('Current URL: ', window.location.toString());
    if (tab_regex.exec(window.location.toString())) {
        console.log('Current URL is almost same as the target URL (so no action required.');
        return {redirectUrl: details.url}
    }

    console.log('Requested URL: ', details.url);
    if (ignore_regex.exec(details.url)) {
        console.log('Requested URL is in ignore_regex (so no action required.');
        return {redirectUrl: details.url}
    }

    var match = caseId_regex.exec(details.url);
    console.log("matches = " + match);
    if (!match) {
        console.log("no match, so returning the original URL");
        return {redirectUrl: details.url}
    }

    // Get the list of currently opened tabs, to find the target/updating tab
    chrome.tabs.query({currentWindow: true}, function (tabs) {
        // It seems no 'break' in forEach?, so storing id into tab_id
        var tab_id = null;
        tabs.forEach(function (tab) {
            if (tab_id === null && tab.id != details.tabId) {
                if (tab_regex.exec(tab.url)) {
                    tab_id = tab.id;
                    console.log('The target tab is already opened and id is ', tab_id);
                    console.log('and URL is ', tab.url);
                }
            }
        });

        if (tab_id && tab_id != details.tabId) {
            console.log('Closing the new tab as going to re-use existing tab:', tab_id);
            chrome.tabs.remove(details.tabId, function () {
            });
        } else {
            console.log('Could not find the target tab or tab ID is same, so using a new tab.');
            return {redirectUrl: details.url}
        }

        var new_url = "https://atscale2ndorg.lightning.force.com/lightning/r/Case/" + match[2] + "/view";
        //var new_url = "https://na63.salesforce.com/console#%2F" + match[2];
        //var new_url = "https://customers.atscale.com/" + match[2];
        //var new_url = "https://customers.atscale.com/s/case/" + match[2] + "/detail";
        console.log("New URL = " + new_url);
        chrome.tabs.update(tab_id, {"active": true, url: new_url});
    });
}