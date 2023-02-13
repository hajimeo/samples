# Simple H2 client
Limitation: only standard and SELECT SQL statements. No "info classes" etc.

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/h2-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -Xmx16g -jar ./h2-console.jar "/sonatype-work/data/ods" "MV_STORE=FALSE;DATABASE_TO_UPPER=FALSE;LOCK_MODE=0;DEFAULT_LOCK_TIMEOUT=600000"
```
### Execute SQL statement(s)
```
# Batch processing
echo "SQL SELECT statement" | java -jar h2-console.jar <DB file path>

# Pagenation for extreamly large result set
echo "<*SIMPLE* SELECT statement which returns so many rows>" | java -Dpaging=10000 -jar h2-console.jar <DB file path + H2 options>
```

## TODOs:
- Add unit tests
- Replace jline3

## My note:
mvn clean package && cp -v -p ./target/h2-console-1.0-SNAPSHOT.jar ../../misc/h2-console.jar

