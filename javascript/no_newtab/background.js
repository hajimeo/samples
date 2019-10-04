// "persistent": true is required for onBeforeRequest
// Check https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(noNewTab, {
  urls: ['https://*/*', "http://*/*"],
  types: ["main_frame"]
}, ["blocking"]);

// If URL matches below, ignoring (because I'm using another similar extension)
var ignore_regex = new RegExp("^https://(.+\.zendesk\.com/agent/tickets/)");

function noNewTab(req) {
  // NOTE: You can tick Show timestamp in DevTools settings
  console.log("New req:", req);

  if (ignore_regex.exec(req.url)) {
    console.log('Requested URL is in ignore_regex, so no action required.');
    return
  }

  // Get the list of currently opened tabs from *all* windows if initiator is set.
  var queryInfo = (req.initiator) ? {currentWindow: true} : {};
  chrome.tabs.query(queryInfo, function(tabs) {
    // It seems no 'break' in forEach?, so using 'target_tab'.
    var target_tab = null;
    tabs.forEach(function(tab) {
      if (target_tab === null) {
        //console.log('Checking id:' + tab.id + ' url:' + tab.url); // This is for debugging
        if (tab.url.toString() === req.url.toString() && tab.id.toString() !== req.tabId.toString()) {
          target_tab = tab;
        }
      }
    });

    if (target_tab) {
      console.log('Found a target tab which uses same URL:', target_tab);
      chrome.tabs.update(target_tab.id, {"active": true});
      chrome.windows.update(target_tab.windowId, {focused: true});
      chrome.tabs.remove(req.tabId, function() {
        if (chrome.runtime.lastError) {
          console.log("Last Error after chrome.tabs.remove:", chrome.runtime.lastError);
        }
        else {
          console.log('Closed the newly opened tab (req)');
        }
      });
    }
    else {
      console.log('No matching tab, so just redirecting to URL:', req.url);
      return {redirectUrl: req.url}
    }
  });
}