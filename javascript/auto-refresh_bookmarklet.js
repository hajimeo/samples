javascript:if (confirm("Reload this page with 1 minute interval for 480 times")) {
  current = location.href;
  x = 0;
  intervalID = setInterval(function() {
    var newwin = window.open(current, '_blank');
    setTimeout(() => {
      console.log("Reloading ", current);
    }, 5000);
    newwin.close();
    if (++x === 480) {
      window.clearInterval(intervalID);
    }
  }, 55 * 1000);
}