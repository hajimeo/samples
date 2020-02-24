#!/usr/bin/env groovy
// https://www.javaworld.com/article/2073316/dynamic-java-log-levels-with-jmx-loggingmxbean--jconsole--visualvm--and
// -groovy.html
//
// setLogLevel.groovy
//
// This script allows one to control the logging level of a Java application
// using java.util.logging that exposes its LoggingMXBean for management.
// Java applications using java.util.Logging may provide easily controlled logging
// levels even from remote clients.
//
if (!args) {
  println "Usage: setLogLevel loggerName [logLevel] [host:localhost] [port:6786]"
  System.exit(-1)
}
import javax.management.JMX
import javax.management.ObjectName
import javax.management.remote.JMXConnectorFactory
import javax.management.remote.JMXServiceURL
import java.util.logging.LoggingMXBean
import java.util.logging.LogManager

def class_name = args[0]
def log_level = ""
if (args.size() > 1) {
  log_level = args[1]
}
def host = "localhost"
def port = "6786" // Sun Java Web Console JMX
if (args.size() > 2) {
  host = args[2]
}
if (args.size() > 3) {
  port = args[3]
}
def serverUrl = "service:jmx:rmi:///jndi/rmi://${host}:${port}/jmxrmi"
def server = JMXConnectorFactory.connect(new JMXServiceURL(serverUrl)).MBeanServerConnection
def mbeanName = new ObjectName(LogManager.LOGGING_MXBEAN_NAME)
LoggingMXBean mxbeanProxy = JMX.newMXBeanProxy(server, mbeanName, LoggingMXBean.class);

if (log_level.size() == 0) {
  def current_log_level = mxbeanProxy.getLoggerLevel(class_name)
  println("${class_name} = ${current_log_level}")
}
else {
  mxbeanProxy.setLoggerLevel(class_name, log_level.toUpperCase())
}
