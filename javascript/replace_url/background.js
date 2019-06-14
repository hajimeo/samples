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

function replaceUrl(r) {
    console.log("=== Start 'replaceUrl' ================================");
    console.log("Request: r.tabId = " + r.tabId + " | url = " + r.url);

    // TODO: this is not working as expected. always extension url
    //Current URL:  chrome-extension://jmcbnjdefaolmdilieapganbfmpacnlc/_generated_background_page.html
    console.log('Current URL: ', window.location.toString());
    if (tab_regex.exec(window.location.toString())) {
        console.log('Current URL is almost same as the target URL (so no action required.');
        return {redirectUrl: r.url}
    }

    console.log('Requested URL: ', r.url);
    if (ignore_regex.exec(r.url)) {
        console.log('Requested URL is in ignore_regex (so no action required.');
        return {redirectUrl: r.url}
    }

    var match = caseId_regex.exec(r.url);
    console.log("matches = " + match);
    if (!match || match < 3) {
        console.log("no match, so returning the original URL");
        return {redirectUrl: r.url}
    }

    var id = match[2];
    var new_url = "https://atscale2ndorg.lightning.force.com/lightning/r/Case/" + id + "/view";
    //var new_url = "https://na63.salesforce.com/console#%2F" + match[2];
    //var new_url = "https://customers.atscale.com/" + match[2];
    //var new_url = "https://customers.atscale.com/s/case/" + match[2] + "/detail";
    console.log("New URL = " + new_url);

    // Get the list of currently opened tabs, to find the target/updating tab
    chrome.tabs.query({currentWindow: true}, function (tabs) {
        // It seems no 'break' in forEach?, so storing the target tab.
        var target_tab = null;
        tabs.forEach(function (tab) {
            //console.log('Checking id:' + tab.id + ' vs. ' + r.tabId + ' url:' + tab.url);
            if (target_tab === null) {
                if (tab_regex.exec(tab.url)) {
                    target_tab = tab;
                    console.log('Found the target tab to replace URL, which id is ', target_tab.id);
                    console.log('and URL is ', target_tab.url);
                    chrome.tabs.update(target_tab.id, {"active": true});

                    // TODO: This is not working as SalesForce changes URL slightly (potentially salesforce bug?)
                    if (target_tab.url.toString() == new_url.toString()) {
                        console.log('Newly generated URL is exactly same, so nothing to do (TODO: should refresh). url:' + new_url.toString());
                    } else if (target_tab.url.toString() == r.url.toString()) {
                        console.log('Requested URL is exactly same, so nothing to do (TODO: should refresh). url:' + r.url.toString());
                    } else {
                        console.log('executeScript on ' + target_tab.id + ' for url:' + new_url.toString());
                        // To get active one: li.tabItem.slds-context-bar__item.slds-context-bar__item_tab.slds-is-active
                        var inner_script = `
var id = '${id}';
console.log("id: " + id);
var tabs = document.querySelectorAll('li.tabItem.slds-context-bar__item.slds-context-bar__item_tab');
var r = null;
for (i = 0; i < tabs.length; i++) {
    var a = tabs[i].querySelector('a.tabHeader.slds-context-bar__label-action');
    console.log(a.href);
    if (a.href.indexOf(id) > 0) {
        r = a;
        tabs[i].querySelector('button.slds-button.slds-button_icon-container.slds-button_icon-x-small').click();
        tabs[i].querySelector('li.slds-dropdown__item.refreshTab a').click();
        break;
    }
}
if (r) {
    r.click();
} else {
    window.location.href = "https://atscale2ndorg.lightning.force.com/lightning/r/Case/" + id + "/view";
}
`.trim();
                        chrome.tabs.executeScript(target_tab.id, {
                            code: inner_script
                        }, function (results) {
                            console.log(results);
                            if (chrome.runtime.lastError) {
                                console.log("Last Error after executeScript: " + chrome.runtime.lastError.toString());
                                // I think it should exit in here.
                            }
                        });
                    }

                    if (target_tab.id.toString() != r.tabId.toString()) {
                        console.log('Closing the newly opened tab ' + r.tabId.toString());
                        chrome.tabs.remove(r.tabId, function () {
                        });
                    }
                }
            }
        });

        if (!target_tab) {
            console.log('Could not find the target tab or tab ID is same, so using a new tab.');
            return {redirectUrl: r.url}
        }
    });
}