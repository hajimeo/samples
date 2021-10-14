// Copy of https://github.com/niocs/csvsql/blob/master/csvsql.go
package main

import (
	"bufio"
	"database/sql"
	"encoding/hex"
	"fmt"
	"github.com/chzyer/readline"
	_ "github.com/mattn/go-sqlite3"
	"github.com/niocs/sflag"
	"io"
	"io/ioutil"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"os/user"
	"path/filepath"
	"strings"
)

var opt = struct {
	Usage     string "Usage string"
	Load      string "CSV file to load"
	MemDB     bool   "Create DB in :memory: instead of disk. Defaults to false"
	AskType   bool   "Asks type for each field. Uses TEXT otherwise."
	Type      string "Comma separated field types. Can be TEXT/REAL/INTEGER."
	TableName string "Sqlite table name.  Default is csv filename."
	RPI       int    "Rows per insert. Defaults to 100. Reduce if long rows.|100"
	Query     string "Query to run. If not provided, enters interactive mode"
	OutFile   string "File to write csv output to. Defaults to stdout.|/dev/stdout"
	OutDelim  string "Output Delimiter to use. Defaults is comma.|,"
	WorkDir   string "tmp dir to create db in. Defaults to /tmp/|/tmp/"
}{}

func Usage() {
	fmt.Println(`
Usage: csvsql  --Load    <csvfile>
              [--MemDB]             #Creates sqlite db in :memory: instead of disk.
              [--AskType]           #Asks type for each field. Uses TEXT otherwise.
              [--Type  <type1>,...] #Comma separated field types. Can be TEXT/REAL/INTEGER.
              [--TableName]         #Sqlite table name.  Default is csv filename.
              [--Query]             #Query to run. If not provided, enters interactive mode.
              [--RPI]               #Rows per insert. Defaults to 100. Reduce if long rows.
              [--OutFile]           #File to write csv output to. Defaults to stdout.
              [--OutDelim]          #Output Delimiter to use. Defaults is comma.
              [--WorkDir <workdir>] #tmp dir to create db in. Defaults to /tmp/. 
The --WorkDir parameter is ignored if --MemDB is specified.
The --AskType parameter is ignored if --Type  is specified.
The --OutFile parameter is ignored if --Query is NOT specified.
`)
}

func TempFileName(_basedir, prefix string) (string, string) {
	randBytes := make([]byte, 8)
	rand.Read(randBytes)
	tmpDir, err := ioutil.TempDir(_basedir, prefix)
	if err != nil {
		log.Panic(err)
	}
	return tmpDir, filepath.Join(tmpDir, prefix+hex.EncodeToString(randBytes))
}

func InsertToDB(db *sql.DB, queries <-chan string, done chan<- bool) {
	tx, err := db.Begin()
	if err != nil {
		log.Panic(err)
	}
	for {
		query, more := <-queries
		if more {
			_, err := tx.Exec(query)
			if err != nil {
				log.Panic(err)
			}
		} else {
			tx.Commit()
			done <- true
			return
		}
	}
}

func SetType(headerStr string) (fieldsSql string, quoteField []bool, fieldTypes []byte) {
	header := strings.Split(headerStr, ",")
	types := strings.Split(opt.Type, ",")
	for ii, field := range header {
		if len(fieldsSql) > 0 {
			fieldsSql += ","
		}
		typ := strings.ToUpper(types[ii])
		if typ == "INTEGER" || typ == "REAL" {
			fieldsSql += field + " " + typ
		} else {
			typ = "TEXT"
			fieldsSql += field + " " + typ
		}
		if typ == "TEXT" {
			fieldTypes = append(fieldTypes, 0)
			quoteField = append(quoteField, true)
		} else if typ == "INTEGER" {
			fieldTypes = append(fieldTypes, 1)
			quoteField = append(quoteField, false)
		} else if typ == "REAL" {
			fieldTypes = append(fieldTypes, 2)
			quoteField = append(quoteField, false)
		}
	}
	return fieldsSql, quoteField, fieldTypes
}

func AskType(headerStr string, rowStr string) (fieldsSql string, quoteField []bool, fieldTypes []byte) {
	var completer = readline.NewPrefixCompleter(
		readline.PcItem("TEXT"),
		readline.PcItem("INTEGER"),
		readline.PcItem("REAL"),
	)
	rl, err := readline.NewEx(&readline.Config{
		AutoComplete: completer,
		Prompt:       "Enter type (TAB for options): ",
	})
	if err != nil {
		log.Panic(err)
	}
	header := strings.Split(headerStr, ",")
	value := strings.Split(rowStr, ",")
	for ii, field := range header {
		fmt.Printf("Field: %s  (first value: %s)\n", field, value[ii])
		fieldType, err := rl.Readline()
		if err != nil {
			log.Panic(err)
		}
		fieldType = strings.ToUpper(strings.TrimSpace(fieldType))
		if len(fieldsSql) > 0 {
			fieldsSql += ","
		}
		if fieldType == "INTEGER" || fieldType == "REAL" {
			fieldsSql += field + " " + fieldType
		} else {
			fieldType = "TEXT"
			fieldsSql += field + " " + fieldType
		}
		if fieldType == "TEXT" {
			fieldTypes = append(fieldTypes, 0)
			quoteField = append(quoteField, true)
		} else if fieldType == "INTEGER" {
			fieldTypes = append(fieldTypes, 1)
			quoteField = append(quoteField, false)
		} else if fieldType == "REAL" {
			fieldTypes = append(fieldTypes, 2)
			quoteField = append(quoteField, false)
		}
	}
	return fieldsSql, quoteField, fieldTypes
}

func main() {
	sflag.Parse(&opt)
	if _, err := os.Stat(opt.Load); os.IsNotExist(err) {
		fmt.Println(err)
		Usage()
		os.Exit(1)
	}
	var dbfile string
	var dbdir string
	var headerStr string
	var rowStr string
	var fieldsSql string
	var quoteField []bool
	var fieldTypes []byte
	var query string
	var interactiveMode = len(opt.Query) == 0
	var queryChan = make(chan string, 500)
	var doneChan = make(chan bool)

	if opt.MemDB {
		dbfile = ":memory:"
	} else {
		dbdir, dbfile = TempFileName(opt.WorkDir, "csvsql")
		defer os.RemoveAll(dbdir)
	}

	db, err := sql.Open("sqlite3", dbfile)
	if err != nil {
		log.Panic(err)
	}
	defer db.Close()

	fp, err := os.Open(opt.Load)
	if err != nil {
		log.Panic(err)
	}
	fpBuf := bufio.NewReader(fp)
	headerStr, err = fpBuf.ReadString('\n')
	headerStr = strings.TrimSuffix(headerStr, "\n")
	if err != nil {
		log.Panic(err)
	}
	rowStr, err = fpBuf.ReadString('\n')
	rowStr = strings.TrimSuffix(rowStr, "\n")
	if err == io.EOF {
		if len(rowStr) == 0 {
			log.Println("No data rows")
			os.Exit(1)
		}
	} else if err != nil {
		log.Panic(err)
	}
	if len(opt.Type) > 0 {
		fieldsSql, quoteField, fieldTypes = SetType(headerStr)
	} else if opt.AskType {
		fieldsSql, quoteField, fieldTypes = AskType(headerStr, rowStr)
	} else {
		for _, field := range strings.Split(headerStr, ",") {
			if len(fieldsSql) > 0 {
				fieldsSql += ","
			}
			fieldsSql += field + " TEXT"
			quoteField = append(quoteField, true)
			fieldTypes = append(fieldTypes, 0)
		}
	}
	if len(opt.TableName) == 0 {
		opt.TableName = strings.Split(filepath.Base(opt.Load), ".")[0]
	}
	go InsertToDB(db, queryChan, doneChan)
	query = fmt.Sprintf("CREATE TABLE %s (%s);", opt.TableName, fieldsSql)
	queryChan <- query
	if interactiveMode {
		fmt.Println("Loading csv into table '" + opt.TableName + "'")
	}
	insCnt := 0
	for {
		fieldsSql = ""
		for ii, field := range strings.Split(rowStr, ",") {
			if len(fieldsSql) > 0 {
				fieldsSql += ","
			}
			if quoteField[ii] {
				fieldsSql += "\"" + field + "\""
			} else {
				field = strings.TrimSpace(field)
				if field == "" {
					field = "NULL"
				}
				fieldsSql += field
			}
		}
		if insCnt == 0 {
			query = "INSERT INTO " + opt.TableName + " VALUES (" + fieldsSql + ")"
		} else if insCnt == opt.RPI {
			query += ";"
			queryChan <- query
			insCnt = 0
			query = "INSERT INTO " + opt.TableName + " VALUES (" + fieldsSql + ")"
		} else {
			query += ",(" + fieldsSql + ")"
		}
		insCnt++
		rowStr, err = fpBuf.ReadString('\n')
		rowStr = strings.TrimSuffix(rowStr, "\n")
		if err == io.EOF {
			break
		} else if err != nil {
			log.Panic(err)
		}
	}
	if len(query) > 0 {
		query += ";"
		queryChan <- query
	}
	close(queryChan)
	<-doneChan
	if interactiveMode {
		interactive(db, fieldTypes)
	} else {
		execQuery(db, fieldTypes)
	}
}

func printRows(fp *os.File, rows *sql.Rows, fieldTypes []byte) {
	cols, err := rows.Columns()
	if err != nil {
		log.Panic(err)
	}
	CtrlC := make(chan os.Signal, 2)
	signal.Notify(CtrlC, os.Interrupt)
	var stopPrinting = false
	go func() {
		_, ok := <-CtrlC
		if ok {
			stopPrinting = true
		}
	}()
	fmt.Fprintln(fp, strings.Join(cols, opt.OutDelim))
	colLen := len(cols)
	rowStr := make([]sql.NullString, colLen)
	rowInt := make([]sql.NullInt64, colLen)
	rowReal := make([]sql.NullFloat64, colLen)
	rowIface := make([]interface{}, colLen)
	for ii := 0; ii < colLen; ii++ {
		if fieldTypes[ii] == 0 { //TEXT
			rowIface[ii] = &rowStr[ii]
		} else if fieldTypes[ii] == 1 { //INTEGER
			rowIface[ii] = &rowInt[ii]
		} else if fieldTypes[ii] == 2 { //REAL
			rowIface[ii] = &rowReal[ii]
		}
	}
	for rows.Next() {
		rows.Scan(rowIface...)
		for ii := 0; ii < colLen; ii++ {
			if ii > 0 {
				fmt.Fprint(fp, opt.OutDelim)
			}
			if fieldTypes[ii] == 0 { //TEXT
				v, err := rowStr[ii].Value()
				if err != nil {
					log.Panic(err)
				}
				if v != nil {
					fmt.Fprint(fp, v)
				}
			} else if fieldTypes[ii] == 1 { //INTEGER
				v, err := rowInt[ii].Value()
				if err != nil {
					log.Panic(err)
				}
				if v != nil {
					fmt.Fprint(fp, v)
				}
			} else if fieldTypes[ii] == 2 { //REAL
				v, err := rowReal[ii].Value()
				if err != nil {
					log.Panic(err)
				}
				if v != nil {
					fmt.Fprint(fp, v)
				}
			}
		}
		fmt.Fprintln(fp)
		if stopPrinting {
			rows.Close()
			break
		}
	}
	signal.Stop(CtrlC)
	close(CtrlC)
}

func execQuery(db *sql.DB, fieldTypes []byte) {
	rows, err := db.Query(opt.Query)
	if err != nil {
		log.Panic(err)
	}
	defer rows.Close()
	fp, err := os.Create(opt.OutFile)
	if err != nil {
		log.Panic(err)
	}
	printRows(fp, rows, fieldTypes)
}

func interactive(db *sql.DB, fieldTypes []byte) {
	usr, err := user.Current()
	if err != nil {
		log.Panic(err)
	}
	rl, err := readline.NewEx(&readline.Config{
		Prompt:                 "sql> ",
		HistoryFile:            usr.HomeDir + "/.csvsql.history",
		DisableAutoSaveHistory: true,
	})
	if err != nil {
		log.Panic(err)
	}
	defer rl.Close()

	fmt.Println("Type \\q to exit")
	var queryLines []string
	for {
		line, err := rl.Readline()
		if err == readline.ErrInterrupt {
			queryLines = queryLines[:0]
			rl.SetPrompt("sql> ")
			continue
		} else if err == io.EOF {
			break
		} else if err != nil {
			log.Panic(err)
		}
		line = strings.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		if line == "\\q" {
			break
		}
		if line == "exit" {
			break
		}

		queryLines = append(queryLines, line)
		if !strings.HasSuffix(line, ";") {
			rl.SetPrompt(">>> ")
			continue
		}
		query := strings.Join(queryLines, " ")
		queryLines = queryLines[:0]
		rl.SetPrompt("sql> ")
		rl.SaveHistory(query)
		rows, err := db.Query(query)
		if err != nil {
			fmt.Println(err)
			continue
		}
		defer rows.Close()
		printRows(os.Stdin, rows, fieldTypes)
	}
}
