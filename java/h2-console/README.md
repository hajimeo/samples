# Simple H2 client
Limitation: only standard and SELECT SQL statements. H2 specific commands/queries may not work.

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/h2-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -Xmx16g -jar ./h2-console.jar "/sonatype-work/data/ods.h2.db"
```
### Execute SQL statement(s)
```
# Batch processing
echo "SQL SELECT statement" | java -jar h2-console.jar <DB file path>

# Pagenation for extreamly large result set
echo "<*SIMPLE* SELECT statement which returns so many rows>" | java -Dpaging=10000 -jar h2-console.jar <DB file path + H2 options>
```
### Recover database:
Instead of `-jar`, use `-cp`
```
java -Xmx4g -cp ./h2-console.jar org.h2.tools.Recover -dir ./ -db ods
```
NOTE: Recover does not use large heap, but RunScript may need (depending on the size of ods.h2.sql)

## TODOs:
- Add unit tests
- Replace jline3

## My note:
mvn clean package && cp -v -p ./target/h2-console-1.0-SNAPSHOT.jar ../../misc/h2-console.jar

