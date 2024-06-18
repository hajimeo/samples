// From https://kazuhira-r.hatenablog.com/entry/20161126/1480144751
import javax.servlet.http.HttpServletRequest

@RestController
class HelloSessionController {
  def logger = org.slf4j.LoggerFactory.getLogger(getClass())

  @GetMapping('hello')
  def hello(HttpServletRequest request) {
    logger.info(java.time.LocalDateTime.now().toString() + ": access " + request.requestURI)

    def session = request.session
    def now = session.getAttribute('now')
    if (!now) {
      now = java.time.LocalDateTime.now().toString()
      session.setAttribute('now', now)
    }

    '[' + now + '] Hello ' + InetAddress.localHost.hostName + "!!" + System.lineSeparator()
  }

  @GetMapping('health-check')
  def healthCheck(HttpServletRequest request) {
    logger.info(java.time.LocalDateTime.now().toString() + ": access " + request.requestURI)
    'OK ' + InetAddress.localHost.hostName + "!!" + System.lineSeparator()
  }
}