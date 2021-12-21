// NOTE: need to allow the popup, maybe?
javascript:if (confirm("Pinging this URL with 3 minute interval for 120 times")) {
  current = location.href;
  x = 0;
  intervalID = setInterval(function() {
    var newwin = window.open(current, '_blank');
    setTimeout(function() {
      console.log("Reloading ", current);
    }, 5 * 1000);
    newwin.close();
    if (++x === 120) {
      window.clearInterval(intervalID);
    }
  }, (180 - 5) * 1000);
}