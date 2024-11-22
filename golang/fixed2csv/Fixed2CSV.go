/*
 * This program reads a file which uses fixed width for columns and converts it into CSV format.
 *
 * If LINE_REGEX is set, it uses the regex to extract columns.
 *    export LINE_REGEX='(\S+) (\S+) (\S+) \[([^\]]+)\] "([^"]+)" (\S+) (\S+) (\S+) (\S+) "([^"]+)" \[([^\]]+)\]'
 *    fixed2csv ./log/request.log ./request.csv
 *    TODO: currently rg (f_request2csv) is faster
 *
 * If the input file is a JSON file, this also converts the JSON into CSV format.
 * For example, generating CSV from a json file but under 'application'
 *    fixed2csv ./db/application.json ./application.csv application
 */

package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/yukithm/json2csv"
	"io"
	"log"
	"os"
	"regexp"
	"strings"
)

var NumericRegexp = regexp.MustCompile(`^[-+]?[0-9]+\.?[0-9]*$`)
var LineRegex = os.Getenv("LINE_REGEX")
var LineRegexp *regexp.Regexp
var Delimiter = os.Getenv("LINE_DELIMITER")

func nonSpacePos(line string) []int {
	positions := make([]int, 0)
	// TODO: Because of below, headers can't contain space...
	words := strings.Fields(line)
	for _, w := range words {
		i := strings.Index(line, w)
		if len(positions) == 0 && i > 0 {
			if len(strings.Trim(line[0:i], " ")) == 0 {
				continue
			}
		}
		positions = append(positions, i)
	}
	return positions
}

func line2CSV(line string, positions []int) string {
	from := 0
	csvStr := ""
	if len(Delimiter) == 0 {
		Delimiter = ","
	}
	for _, pos := range positions {
		col := line[from:pos]
		if len(csvStr) > 0 {
			csvStr += Delimiter
		}
		if !NumericRegexp.MatchString(col) {
			csvStr += "\"" + strings.Trim(col, " ") + "\""
		} else {
			csvStr += strings.Trim(col, " ")
		}
		from = pos
	}
	return csvStr
}

func matches2CSV(matches []string) string {
	csvStr := ""
	if len(Delimiter) == 0 {
		Delimiter = ","
	}
	for _, col := range matches {
		if len(csvStr) > 0 {
			csvStr += Delimiter
		}
		// Special handling for treating '-' as null
		if col == "-" {
			continue
		}
		if !NumericRegexp.MatchString(col) {
			csvStr += "\"" + strings.Trim(col, " ") + "\""
		} else {
			csvStr += strings.Trim(col, " ")
		}
	}
	return csvStr
}

func jsList2csv(jsonListObj []interface{}) string {
	// NOTE: Assuming all records have same keys in same order
	csv, err := json2csv.JSON2CSV(jsonListObj)
	if err != nil {
		log.Fatal(err)
	}
	// CSV bytes convert & writing...
	b := &bytes.Buffer{}
	wr := json2csv.NewCSVWriter(b)
	err = wr.WriteCSV(csv)
	if err != nil {
		log.Fatal(err)
	}
	wr.Flush()
	return b.String()
}

func processJson(inFile string, outputFile *os.File, jsonKey string) bool {
	jsonBytes, err := os.ReadFile(inFile)
	if err != nil {
		fmt.Printf("Error reading %s as JSON file: %v\n", inFile, err)
		return false
	}
	var jsonObject []interface{}
	if len(jsonKey) == 0 {
		err = json.Unmarshal(jsonBytes, &jsonObject)
	} else {
		var jsonObjectTmp map[string]interface{}
		err = json.Unmarshal(jsonBytes, &jsonObjectTmp)
		jsonObject = jsonObjectTmp[jsonKey].([]interface{})
	}
	if err != nil {
		fmt.Printf("Error parsing %s as JSON file: %v\n", inFile, err)
		return false
	}
	csvStr := jsList2csv(jsonObject)
	_, err = io.WriteString(outputFile, csvStr)
	if err != nil {
		fmt.Printf("Error writing %s as JSON into %v file: %v\n", inFile, outputFile, err)
		return false
	}
	fmt.Printf("Created %s\n", outputFile.Name())
	return true
}

func processFile(inFile string, outputFile *os.File, lineRegex string) bool {
	inputFile, err := os.Open(inFile)
	if err != nil {
		fmt.Println(err)
		return false
	}
	defer inputFile.Close()

	if len(lineRegex) > 0 {
		LineRegexp = regexp.MustCompile(lineRegex)
	}
	var positions []int = nil
	scanner := bufio.NewScanner(inputFile)
	// If first line, assuming as header, which can be used to determine the width
	isFirstLine := true
	for scanner.Scan() {
		line := scanner.Text()
		// Ignore comment lines
		if strings.HasPrefix(line, "#") {
			continue
		}

		// Decide use regex or treat as fixed width
		if len(lineRegex) > 0 {
			matches := LineRegexp.FindStringSubmatch(line)
			if matches == nil {
				// If first line, it might be header so that it may not match with regex, so just printing
				if isFirstLine {
					fmt.Fprintln(outputFile, "# "+line)
				}
				// otherwise continue
			} else {
				csvStr := matches2CSV(matches[1:])
				fmt.Fprintln(outputFile, csvStr)
			}
		} else {
			if isFirstLine {
				positions = nonSpacePos(line)
				if positions == nil || len(positions) == 0 {
					fmt.Println("Could not determine the width from the below line:\n" + line)
					return false
				}
			}
			csvStr := line2CSV(line, positions)
			fmt.Fprintln(outputFile, csvStr)
		}
		isFirstLine = false
	}
	// Check for errors.
	if err := scanner.Err(); err != nil {
		fmt.Println(err)
		return false
	}
	fmt.Printf("Created %s\n", outputFile.Name())
	return true
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide an input file which uses fixed width for columns or a JSON file.")
		return
	}
	inFile := os.Args[1]
	outFile := inFile + ".csv"
	if len(os.Args) > 2 && len(os.Args[2]) > 0 {
		outFile = os.Args[2]
	}
	jsonKey := ""
	if len(os.Args) > 3 && len(os.Args[3]) > 0 {
		jsonKey = os.Args[3]
	}

	outputFile, err := os.Create(outFile)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer outputFile.Close()

	if strings.HasSuffix(inFile, ".json") {
		processJson(inFile, outputFile, jsonKey)
		return
	}
	processFile(inFile, outputFile, LineRegex)
}
