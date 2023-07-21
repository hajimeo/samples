#!/usr/bin/env groovy
import java.nio.file.Files
def path = new File(args[0]).toPath()
System.out.println("Probing Content Type for file: " + path)
String type = Files.probeContentType(path)
System.out.println("File Content type: " + type)