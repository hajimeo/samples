// From https://kazuhira-r.hatenablog.com/entry/20161126/1480144751
import javax.servlet.http.HttpServletRequest

@RestController
class HelloController {
  def logger = org.slf4j.LoggerFactory.getLogger(getClass())

  @GetMapping('hello')
  def hello(HttpServletRequest request) {
    logger.info(java.time.LocalDateTime.now().toString() + ": access " + request.requestURI)
    'Hello ' + InetAddress.localHost.hostName + "!!" + System.lineSeparator()
  }
}