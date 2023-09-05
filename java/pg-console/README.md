# Simple PostgreSQL client

## Download the latest version:
```
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/pg-console.jar"
```

## Usage Examples:
### Start interactive console
```
java -jar ./pg-console.jar <jdbcURL> <dbUser> <dbPwd>
```
or
```
export _PGDB_USER="dbuser" _PGDB_PWD="dbpwd"
java -jar ./pg-console.jar <jdbcURL>
```
or
```
source ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
java -jar ./pg-console.jar "$jdbcUrl" "$username" "$password"
```
or
```
source /dev/stdin <<< $(cat /proc/$(ps auxwww | grep -w 'NexusMain' | awk '{print $2}' | head -n1)/environ | tr '\0' '\n' | grep -E '^(JDBC_URL|DB_USER|DB_PWD)=')
java -jar ./pg-console.jar "$JDBC_URL" "$DB_USER" "$DB_PWD"
```

### Execute SQL statement(s)
Connection testing:
```
for i in {1..3}; do time echo "SELECT 1 as c1" | java -jar ./pg-console.jar "$JDBC_URL" "$DB_USER" "$DB_PWD" 2>&1 | grep "Elapsed"; done
```
# Batch processing
echo "SQL SELECT statement" | java -jar ./pg-console.jar <jdbcUrl> <dbUser> <dbPwd>

# TODO: Pagenation for extreamly large result set
echo "<*SIMPLE* SELECT statement which returns so many rows>" | java -Dpaging=10000 -jar pg-console.jar <jdbcUrl> <dbUser> <dbPwd>
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

