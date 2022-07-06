# Simple OrientDB client  
Limitation: only standard and SELECT SQL statements. No "info classes" etc.

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -jar ./orient-console.jar "./sonatype-work/nexus3/db/component"

# or with a small .bak (zip) file:
java -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak

# or with larger .bak file (or use env:_EXTRACT_DIR instead of -DextractDir):
java -DextractDir=./component -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak
```
### Start as a server
```
java -Dserver=true -jar ./orient-console.jar "./sonatype-work/nexus3/db/component"

# Then connect from another PC
java -jar ./orient-console.jar "remote:node-nxrm-ha1.standalone.localdomain/component"
```
### Execute SQL statement(s)
```
# Batch processing (env:_EXPORT_PATH can be used instead of -DexportPath):
echo "SQL SELECT statement" | java -DexportPath=./result.json -jar orient-console.jar <directory path|.bak file path>

# Pagenation for extreamly large result set
echo "SIMPLE SELECT statement which returns so many rows" | java -DexportPath=./result_paged.json -Dpaging=10000 -jar orient-console.jar <directory path|.bak file path>
```

## TODOs:
- Add unit tests 
- Replace jline3 

## My note:
mvn clean package && cp -v -p ./target/orient-console-1.0-SNAPSHOT.jar ../../misc/orient-console.jar

