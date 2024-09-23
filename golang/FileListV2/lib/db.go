// Package lib: DB related functions which are not heavily related to the main (business) logic.
package lib

import (
	"FileListV2/common"
	"database/sql"
	"fmt"
	h "github.com/hajimeo/samples/golang/helpers"
	"regexp"
	"strings"
	"time"
)

func GenDbConnStrFromFile(filePath string) string {
	props, _ := h.ReadPropertiesFile(filePath)
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
		// NOTE: probably need to escape the 'params'?
		params = " " + strings.ReplaceAll(matches[4], "&", " ")
	}
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params)
	props["password"] = "********"
	h.Log("INFO", fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params))
	return connStr
}

func OpenDb(dbConnStr string) *sql.DB {
	if len(dbConnStr) == 0 {
		h.Log("DEBUG2", "Empty DB connection string")
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

func Query(query string, db *sql.DB, slowMs int64) *sql.Rows {
	slowMsg := "WARN  Slow query: " + query
	if common.Debug || slowMs == 0 {
		// If debug mode or slowMs is 0, always log as DEBUG
		slowMs = 0
		slowMsg = h.TruncateStr("DEBUG query: "+query, 1000)
	}
	defer h.Elapsed(time.Now().UnixMilli(), slowMsg, slowMs)
	if db == nil { // For unit tests
		return nil
	}
	rows, err := db.Query(query)
	if err != nil {
		h.Log("ERROR", query)
		panic(err.Error())
	}
	return rows
}

func GetRow(rowCur *sql.Rows, cols []string) []interface{} {
	if cols == nil || len(cols) == 0 {
		h.Log("ERROR", "No column information")
		return nil
	}
	vals := make([]interface{}, len(cols))
	for i := range cols {
		vals[i] = &vals[i]
	}
	err := rowCur.Scan(vals...)
	if err != nil {
		h.Log("WARN", "rows.Scan returned error: "+err.Error())
		return nil
	}
	return vals
}
