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

    // TODO: this is not working as expected. always extension url
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

    var new_url = "https://atscale2ndorg.lightning.force.com/lightning/r/Case/" + match[2] + "/view";
    //var new_url = "https://na63.salesforce.com/console#%2F" + match[2];
    //var new_url = "https://customers.atscale.com/" + match[2];
    //var new_url = "https://customers.atscale.com/s/case/" + match[2] + "/detail";
    console.log("New URL = " + new_url);

    // Get the list of currently opened tabs, to find the target/updating tab
    chrome.tabs.query({currentWindow: true}, function (tabs) {
        // It seems no 'break' in forEach?, so storing the target tab.
        var target_tab = null;
        tabs.forEach(function (tab) {
            //console.log('Checking id:' + tab.id + ' vs. ' + details.tabId + ' url:' + tab.url);
            if (target_tab === null) {
                if (tab_regex.exec(tab.url)) {
                    target_tab = tab;
                    console.log('Found the target tab to replace URL, which id is ', target_tab.id);
                    console.log('and URL is ', target_tab.url);

                    // TODO: This is not working as SalesForce changes URL slightly (potentially salesforce bug?)
                    if (target_tab.url.toString() == new_url.toString()) {
                        console.log('New URL is exactly same, so that just focusing. url:' + new_url.toString());
                        chrome.tabs.update(target_tab.id, {"active": true});
                    } else if (target_tab.url.toString() == details.url.toString()) {
                        console.log('URL is exactly same, so that just focusing. url:' + details.url.toString());
                        chrome.tabs.update(target_tab.id, {"active": true});
                    } else {
                        console.log('Redirecting to url:' + new_url.toString());
                        chrome.tabs.update(target_tab.id, {"active": true, url: new_url});
                    }

                    if (target_tab.id.toString() != details.tabId.toString()) {
                        console.log('Closing the newly opened tab ' + details.tabId.toString());
                        chrome.tabs.remove(details.tabId, function () { });
                    }
                }
            }
        });

        if (!target_tab) {
            console.log('Could not find the target tab or tab ID is same, so using a new tab.');
            return {redirectUrl: details.url}
        }
    });
}