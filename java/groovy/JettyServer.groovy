#!/usr/bin/env groovy
// https://gist.github.com/renatoathaydes/8ad276cedd515f8ff5fc
// TODO: convert to HTTPS

import org.eclipse.jetty.server.Server
import org.eclipse.jetty.servlet.*
import groovy.servlet.*

// TODO: change to the latest version
@Grab(group='org.eclipse.jetty.aggregate', module='jetty-all', version='7.6.15.v20140411')
def startJetty() {
  def server = new Server(8080)

  def handler = new ServletContextHandler(ServletContextHandler.SESSIONS)
  handler.contextPath = '/'
  handler.resourceBase = '.'
  handler.welcomeFiles = ['index.html']
  handler.addServlet(GroovyServlet, '/scripts/*')
  def filesHolder = handler.addServlet(DefaultServlet, '/')
  filesHolder.setInitParameter('resourceBase', './public')

  server.handler = handler
  server.start()
}

println "Starting Jetty, press Ctrl+C to stop."
startJetty()