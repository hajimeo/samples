# Simple OrientDB client  
Limitation: only standard and SELECT SQL statements. No "info classes" etc.

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
```

## Usage Examples:
```
# Start interactive console:
java -jar ./orient-console.jar ./sonatype-work/nexus3/db/component
# or with small .bak (zip) file:
java -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak
# or with larger .bak file (or use env:_EXTRACT_DIR instead of -DextractDir):
java -DextractDir=./component -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak

# Batch processing (env:_EXPORT_PATH can be used instead of -DexportPath):
echo "SQL SELECT statement" | java -DexportPath=./result.json -jar orient-console.jar <directory path|.bak file path>
```

## TODOs:

- Add unit tests 
- Replace jline3 
- Convert to JSON without using ODocument.toJSON()
- Support DELETE statement? (but may not be necessary)
```
=> DELETE FROM healthcheckconfig WHERE @rid in (SELECT rid FROM (SELECT MIN(@rid) as rid, property_name, COUNT(*) as c FROM healthcheckconfig GROUP BY property_name) WHERE c > 1)
java.lang.ClassCastException: java.lang.Integer cannot be cast to java.util.List
at Main.execQueries(Main.java:84)
at Main.readLineLoop(Main.java:141)
at Main.main(Main.java:277)
```

## My note:
cp -p ~/IdeaProjects/samples/java/orient-console/target/orient-console-1.0-SNAPSHOT-jar-with-dependencies.jar ~/IdeaProjects/samples/misc/orient-console.jar

