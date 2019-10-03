// "persistent": true is required for onBeforeRequest
// Check https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(noNewTab, {
  urls: ['https://*/*', "http://*/*"],
  types: ["main_frame"]
}, ["blocking"]);

function noNewTab(req) {
  // NOTE: You can tick Show timestamp in DevTools settings
  console.log("New req:", req);

  // Get the list of currently opened tabs from *all* windows.
  chrome.tabs.query({currentWindow: false}, function(tabs) {
    // It seems no 'break' in forEach?, so using 'target_tab'.
    var target_tab = null;
    tabs.forEach(function(tab) {
      //console.log('Checking tab:', tab);
      if (target_tab === null) {
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