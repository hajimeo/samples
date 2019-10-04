// NOTE: "persistent": true is required for onBeforeRequest in the manifest.
// Check https://developer.chrome.com/apps/match_patterns for url match pattern. Also '#' + '*' doesn't work as it is named alias
chrome.webRequest.onBeforeRequest.addListener(replaceUrl, {
  urls: ['https://*.zendesk.com/agent/tickets/*', 'http://*.zendesk.com/agent/tickets/*'],
  types: ["main_frame"]
}, ["blocking"]);

// Replacing the URL if below regex matches
var tab_regex = new RegExp("^https?://.+\.zendesk\.com/agent/");
// Finding case|ticket id from the URL
var id_regex = new RegExp("^https?://(.+\.zendesk\.com/agent/tickets/)([0-9]+)");
// If URL matches below, ignoring (not doing anything), but currently not using.
var ignore_regex = new RegExp("^https?://currently_not_in_use");

function replaceUrl(req) {
  console.log("New req:", req);

  if (ignore_regex.exec(req.url)) {
    console.log('Requested URL is in ignore_regex, so no action required.');
    return
  }

  var match = id_regex.exec(req.url);
  console.log("matches:", match);
  if (!match || match < 3) {
    console.log("no match, so returning the original URL.");
    return {redirectUrl: req.url}
  }

  var id = match[2];
  // If you need to replace the URL, edit below
  //var new_url = "https://TODO_aaaaaaa/" + id + "/extra_path";
  //console.log("New URL = " + new_url);
  var new_url = req.url;

  // Get the list of currently opened tabs from *all* windows if initiator is set.
  var queryInfo = (req.initiator) ? {currentWindow: true} : {};
  console.log("queryInfo:", queryInfo);
  chrome.tabs.query(queryInfo, function(tabs) {
    // TODO: It seems no 'break' in forEach?, so using 'target_tab' to decide if it's already found or not.
    var target_is_active = false;
    var target_tab = null;
    // Finding an active tab first as there might be multiple tabs for same/similar URL tabs opened.
    tabs.forEach(function(tab) {
      if (!target_is_active && tab.active && tab_regex.exec(tab.url) && req.tabId.toString() !== tab.id.toString()) {
        target_is_active = true;
        target_tab = tab;
        console.log('Found active and target tab:', target_tab);
      }
    });

    if (target_tab === null) {
      tabs.forEach(function(tab) {
        if (target_tab === null) {
          //console.log('Checking id:' + tab.id + ' url:' + tab.url); // This is for DEBUG
          //console.log(tab); // This is for DEBUG
          if (tab_regex.exec(tab.url)) {
            target_tab = tab;
            console.log('Found a target tab:', target_tab);
          }
        }
      });
    }

    if (!target_tab) {
      console.log('Could not find any tab, so using the newly opened tab.');
      return {redirectUrl: req.url}
    }

    if (!target_is_active) {
      console.log('Activating the target tab id: ', target_tab.id);
      chrome.tabs.update(target_tab.id, {"active": true});
      chrome.windows.update(target_tab.windowId, {focused: true});
    }

    if (target_tab.url.toString() === new_url.toString()) {
      console.log('New URL is exactly same as the target (TODO: should refresh|reload?): ', new_url);
      return
    }

    // Below two lines are if not using executeScript
    //console.log('Updating tab id:' + target_tab.id + ' with url: ', new_url);
    //chrome.tabs.update(target_tab.id, {url: new_url});
    console.log('executeScript on ' + target_tab.id + ' with the match id: ', id);
    var inner_script = `
var _id = '${id}';
console.log("_id: " + _id);
document.querySelector('a.search-icon').click();
document.querySelector('#mn_1').value=_id;
document.querySelector('a.advanced-search').click();
true;
`.trim();
    chrome.tabs.executeScript(target_tab.id, {
      code: inner_script
    }, function(results) {
      if (chrome.runtime.lastError) {
        console.log("Last Error after executeScript: " + chrome.runtime.lastError.toString());
        return {redirectUrl: req.url}
      }
      if (results && results.length > 0 && results[0]) {
        console.log("An inner tab *may* be clicked!", results);
      }
      else {
        // If results is empty, just change the URL.
        console.log('Unknown executeScript result:', results);
        return {redirectUrl: req.url}
      }
    });

    // If more than one tab are opened and one is active, triggering this extension may end up closing active tab because of below.
    if (!target_is_active && target_tab.id.toString() !== req.tabId.toString()) {
      chrome.tabs.remove(req.tabId, function() {
        if (chrome.runtime.lastError) {
          console.log("Last Error after chrome.tabs.remove:", chrome.runtime.lastError);
        }
        else {
          console.log('Closed the newly opened tab (req)');
        }
      });
    }
  });
}