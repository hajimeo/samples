# Simple PostgreSQL client

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/pg-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -Xmx16g -jar ./pg-console.jar <jdbcURL> <dbUser> <dbPwd>
```
or
```
export _PGDB_USER="dbuser" _PGDB_PWD="dbpwd"
java -Xmx16g -jar ./pg-console.jar <jdbcURL>
```
### Execute SQL statement(s)
```
# Batch processing
echo "SQL SELECT statement" | java -jar ./pg-console.jar <jdbcUrl>

# TODO: Pagenation for extreamly large result set
echo "<*SIMPLE* SELECT statement which returns so many rows>" | java -Dpaging=10000 -jar pg-console.jar <jdbcUrl>
```
#### TODO: Export table(s)
```
export public.* to ./export_dir
```

## TODOs:
- Add unit tests
- Replace jline3

## My note:
```
mvn clean package && cp -v -p ./target/pg-console-1.0-SNAPSHOT.jar ../../misc/pg-console.jar;
```

