// "persistent": true is required for onBeforeRequest
// Check https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(noNewTab, {
    urls: ['https://*/*', "http://*/*"],
    types: ["main_frame"]
}, ["blocking"]);

var tab_regex = new RegExp("^http.?://(.+)");
//var ignore_regex = new RegExp("");

function noNewTab(r) {
    console.log("=== Start 'noNewTab' ================================");
    console.log("Request: r.tabId = " + r.tabId + " | url = " + r.url);

    // TODO: this is not working as expected. always extension url
    //Current URL:  chrome-extension://jmcbnjdefaolmdilieapganbfmpacnlc/_generated_background_page.html
    console.log('Current URL: ', window.location.toString());
    if (tab_regex.exec(window.location.toString())) {
        console.log('Current URL is almost same as the target URL (so no action required.');
        return {redirectUrl: r.url}
    }

    console.log('Requested URL: ', r.url);
    //if (ignore_regex.exec(r.url)) {
    //    console.log('Requested URL is in ignore_regex (so no action required.');
    //    return {redirectUrl: r.url}
    //}

    // If customising new_url, add javascript code in below
    var new_url = r.url;
    console.log("New URL = " + new_url);

    // Get the list of currently opened tabs, to find the target/updating tab
    chrome.tabs.query({currentWindow: true}, function (tabs) {
        // It seems no 'break' in forEach?, so storing the target tab.
        var target_tab = null;
        tabs.forEach(function (tab) {
            //console.log('Checking id:' + tab.id + ' vs. ' + r.tabId + ' url:' + tab.url);
            if (target_tab === null) {
                if (tab.url.toString() == new_url.toString() && tab.id.toString() != r.tabId.toString()) {
                    target_tab = tab;
                    console.log('Found the target tab which uses same URL but different tab (id):', target_tab.id);
                    console.log('and URL is ', target_tab.url);
                    chrome.tabs.update(target_tab.id, {"active": true});
                    console.log('Closing the newly opened tab ' + r.tabId.toString());
                    chrome.tabs.remove(r.tabId, function () {
                    });
                }
            }
        });

        if (!target_tab) {
            console.log('Could not find the target tab or tab ID is same, so using a new tab.');
            return {redirectUrl: r.url}
        }
    });
}