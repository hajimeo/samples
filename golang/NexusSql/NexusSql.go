/*
#go mod init github.com/hajimeo/samples/golang/NexusSql
go mod tidy
env GOOS=linux GOARCH=amd64 go build -o ../../misc/nexus-sql_Linux_amd64 NexusSql.go && \
env GOOS=darwin GOARCH=amd64 go build -o ../../misc/nexus-sql_Darwin_amd64 NexusSql.go && \
env GOOS=darwin GOARCH=arm64 go build -o ../../misc/nexus-sql_Darwin_arm64 NexusSql.go && date

SELECT name, REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository;
SELECT REGEXP_REPLACE(REGEXP_REPLACE(blob_ref, '^[^:]+:', ''), '@.+', '') AS blobId from maven2_asset_blob;
*/

package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/hajimeo/samples/golang/helpers"
	_ "github.com/lib/pq"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

func usage() {
	fmt.Println(`
Connect to PostgreSQL and return the result based on the command arguments
    
HOW-TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/NexusSql/README.md`)
	flag.PrintDefaults()
}

// Arguments
// var _APPTYPE *string
// var _ACTION *string
var _DB_CON_STR *string
var _SQL *string
var _DEBUG *bool

func _setGlobals() {
	//_APPTYPE = flag.String("t", "nxrm", "Application Type [nxrm|nxiq] Default is nxrm")
	//_ACTION = flag.String("a", "", "empty for all or [db-check|data-size|data-export]")
	_DB_CON_STR = flag.String("c", "./", "DB Connection string or path to DB connection config file (nexus-store.properties or config.yml")
	_SQL = flag.String("q", "SELECT 'ok' as connection", "SQL query")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	flag.Parse()
}

type AppConfigProperties map[string]string

func readPropertiesFile(filename string) (AppConfigProperties, error) {
	config := AppConfigProperties{}

	if len(filename) == 0 {
		return config, nil
	}
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if equal := strings.Index(line, "="); equal >= 0 {
			if key := strings.TrimSpace(line[:equal]); len(key) > 0 {
				value := ""
				if len(line) > equal {
					value = strings.TrimSpace(line[equal+1:])
				}
				config[key] = value
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return config, nil
}

func buildConnStringFromFileForNXRM(filePath string) string {
	config, err := readPropertiesFile(filePath)
	if err != nil {
		helpers.Log("ERROR", err.Error())
		return ""
	}
	return genDbConnStrNXRM(config)
}

func genDbConnStrNXRM(props AppConfigProperties) string {
	jdbcPtn := regexp.MustCompile(`jdbc:postgresql://([^/:]+):?(\d*)/([^?]+)\??(.*)`)
	props["jdbcUrl"] = strings.ReplaceAll(props["jdbcUrl"], "\\", "")
	matches := jdbcPtn.FindStringSubmatch(props["jdbcUrl"])
	if matches == nil {
		props["password"] = "********"
		panic(fmt.Sprintf("No 'jdbcUrl' in props: %v", props))
	}
	hostname := matches[1]
	port := matches[2]
	database := matches[3]
	if len(port) == 0 {
		port = "5432"
	}
	params := ""
	if len(matches) > 3 {
		// TODO: probably need to escape?
		params = " " + strings.ReplaceAll(matches[4], "&", " ")
	}
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params)
	props["password"] = "********"
	log.Printf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params)
	return connStr
}

func _elapsed(startTsMs int64, message string, thresholdMs int64) {
	//elapsed := time.Since(start)
	elapsed := time.Now().UnixMilli() - startTsMs
	if elapsed >= thresholdMs {
		log.Printf("%s (%dms)", message, elapsed)
	}
}

func openDb(dbConnStr string) *sql.DB {
	if len(dbConnStr) == 0 {
		return nil
	}
	if !strings.Contains(dbConnStr, "sslmode") {
		dbConnStr = dbConnStr + " sslmode=disable"
	}
	db, err := sql.Open("postgres", dbConnStr)
	if err != nil {
		// If DB connection issue, let's stop the script
		panic(err.Error())
	}
	//db.SetMaxOpenConns(*_CONC_1)
	//err = db.Ping()
	return db
}

func queryDb(query string, db *sql.DB) *sql.Rows {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Executed "+query, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow query:"+query, 100)
	}
	if db == nil { // For unit tests
		return nil
	}
	rows, err := db.Query(query)
	if err != nil {
		panic(err.Error())
	}
	return rows
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}
	_setGlobals()
	if _, err := os.Stat(*_DB_CON_STR); err == nil {
		*_DB_CON_STR = buildConnStringFromFileForNXRM(*_DB_CON_STR)
	}

	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	rows := queryDb(*_SQL, db)
	if rows == nil { // For unit tests
		return
	}
	defer rows.Close()
	columns, err := rows.Columns()
	if err != nil {
		panic(err)
	}
	count := len(columns)
	//tableData := make([]map[string]interface{}, 0)
	values := make([]interface{}, count)
	valuePtrs := make([]interface{}, count)
	fmt.Print("[")
	isFirstLine := true
	for rows.Next() {
		for i := 0; i < count; i++ {
			valuePtrs[i] = &values[i]
		}
		rows.Scan(valuePtrs...)
		entry := make(map[string]interface{})
		for i, col := range columns {
			var v interface{}
			val := values[i]
			b, ok := val.([]byte)
			if ok {
				v = string(b)
			} else {
				v = val
			}
			entry[col] = v
		}
		jsonData, err := json.Marshal(entry)
		//jsonData, err := json.MarshalIndent(entry, "", "  ")
		if err != nil {
			panic(err)
		}
		line := string(jsonData)
		if len(line) > 0 {
			if !isFirstLine {
				fmt.Print(",")
			} else {
				fmt.Println()
				//fmt.Print("  ")
			}
			fmt.Println(string(jsonData))
			isFirstLine = false
		}
		//tableData = append(tableData, entry)
	}
	fmt.Println("]")
}
