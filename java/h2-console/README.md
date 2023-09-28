# Simple H2 client
Limitation: only standard and SELECT SQL statements. H2 specific commands/queries may not work.  
"h2-console_v200.jar" is for Nexus Repository Manager 3.

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/h2-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -Xmx16g -jar ./h2-console.jar <DB file path>
# or
java -Xmx16g -jar ./h2-console_v200.jar <DB file path>
```
Default H2 options:
```
DATABASE_TO_UPPER=FALSE;LOCK_MODE=0;DEFAULT_LOCK_TIMEOUT=600000
```
If the DB file path end with ".h2.db", "MV_STORE=FALSE" is automatically added. Alternatively, set 'h2Opts' system property to overwrite the default or append some extra DB options in the end of file path if you do not want to overwrite the default:
```
java -Xmx16g -Dh2Opts="<H2 options to overwrite default>" -jar ./h2-console.jar <DB file path;extra H2 options>
```
### Execute SQL statement(s)
```
# Batch processing
echo "SQL SELECT statement" | java -jar ./h2-console.jar <DB file path> [<H2 options>]

# Pagenation for extreamly large result set
echo "<*SIMPLE* SELECT statement which returns so many rows>" | java -Dpaging=10000 -jar h2-console.jar <DB file path> [<H2 options>]
```
#### Export table(s)
```
export public.* to ./export_dir
```
### Recover database:
Instead of `-jar`, use `-cp`
```
java -Xmx4g -cp ./h2-console.jar org.h2.tools.Recover -dir ./ -db ods
```
NOTE: Recover does not use large heap, but RunScript may need (depending on the size of ods.h2.sql)
### Example steps to find a corrupted rows:
Example error:
```
java.lang.IllegalStateException: Error trying to export database: IO Exception: "java.io.IOException: org.h2.jdbc.JdbcSQLException: IO Exception: ""Missing lob entry: 18389"" [90028-196]"; "lob: null table: 118 id: 18389"; SQL statement: 
```
```
# Check if really missing:
SELECT * FROM INFORMATION_SCHEMA.LOBS WHERE TABLE = 118 AND ID = 18389;
# get the table_name to check:
SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT_ESTIMATE, SQL from INFORMATION_SCHEMA.TABLES where ID = 118;

# seems negative table name means orphaned:
echo "select <PK>, <TEXT_column> from <table_name>" | java -jar ~/IdeaProjects/samples/misc/h2-console.jar ./db/ods.h2.db | grep '/* table: -' > missing_lobs.out
```

## TODOs:
- Add unit tests
- Replace jline3

## My note:
```
mvn clean package && cp -v -p ./target/h2-console-1.0-SNAPSHOT.jar ../../misc/h2-console.jar; sed -i .bak 's/>1.4.196</>1.4.200</' ./pom.xml && mvn clean package && cp -v -p ./target/h2-console-1.0-SNAPSHOT.jar ../../misc/h2-console_v200.jar; mv -f -v ./pom.xml.bak ./pom.xml
```

