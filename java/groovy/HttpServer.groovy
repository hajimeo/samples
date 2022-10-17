#!/usr/bin/env groovy
// https://gist.github.com/renatoathaydes/8ad276cedd515f8ff5fc

import com.sun.net.httpserver.HttpServer
int PORT = 8080
HttpServer.create(new InetSocketAddress(PORT), /*max backlog*/ 0).with {
  println "Server is listening on ${PORT}, hit Ctrl+C to exit."
  createContext("/") { http ->
    http.responseHeaders.add("Content-type", "text/plain")
    http.sendResponseHeaders(200, 0)
    http.responseBody.withWriter { out ->
      out << "Hello ${http.remoteAddress.hostName}!\n"
    }
    println "Hit from Host: ${http.remoteAddress.hostName} on port: ${http.remoteAddress.holder.port}"
  }
  start()
}