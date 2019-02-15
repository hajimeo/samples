function validateWhitelist(input) {
  var invalidServers = [];
  var whitelistRegExps = [];
  input = input.trim();
  if (input !== "*") {
    var list = input.split(",");
    for(var i=0; i < list.length; i++) {
      var server = list[i].trim();
      if (!server.match(/lightning\.force\.com$/)) invalidServers.push(server);
      else {
        var re = server.replace(/\.?lightning\.force\.com$/,".lightning.force.com").
          replace(/\./g,"\\.").replace(/\*/g,".*");
        try {
          new RegExp(re);
          whitelistRegExps.push(re);
        } catch(e) {
          // Invalid regular expression
          invalidServers.push(server);
        }
      }
    }
  }
  return {"invalidServers": invalidServers, "whitelistRegExps": whitelistRegExps.join()};
}

function showStatus(message, success) {
  var status = document.getElementById('status');
  status.textContent = message;
  if (success) {
    setTimeout(function() {
      status.textContent = '';
      window.close();
    }, 750);
  }
}

function clearStatus() {
  showStatus('', false);
}

// Saves options to chrome.storage.sync.
function save_options() {
  clearStatus();
  var input = document.getElementById('whitelistServers').value;
  if (input.trim() === "") {
    input = "*";
    document.getElementById('whitelistServers').value = input;
  }
  var whitelistServers = input;
  
  var v = validateWhitelist(whitelistServers);
  if (v["invalidServers"].length > 0) {
    showStatus("Invalid server entries: " + v["invalidServers"].join(), false);
  } else {
    var debugEnabled = document.getElementById("debug").selectedIndex;
    chrome.storage.sync.set({
      whitelistServers: whitelistServers,
      whitelistRegExps: v["whitelistRegExps"],
      debug: debugEnabled
    }, function() {
      // Update status to let user know options were saved.
      document.getElementById("save").disabled = true;
      showStatus("Options saved.", true);
    });
  }
}

// Restores the preferences
// stored in chrome.storage.
function restore_options() {
  // Use default value color = 'red' and likesColor = true.
  chrome.storage.sync.get({
    whitelistServers: '*',
    debug: 1
  }, function(items) {
    document.getElementById('whitelistServers').value = items.whitelistServers;
    document.getElementById("debug").selectedIndex = items.debug;
  });
}
document.addEventListener('DOMContentLoaded', restore_options);
document.getElementById('save').addEventListener('click',
    save_options);