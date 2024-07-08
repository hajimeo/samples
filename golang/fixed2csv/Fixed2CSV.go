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

var nonNumericRegexp = regexp.MustCompile(`[^0-9\-.]`)

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
	for _, pos := range positions {
		col := line[from:pos]
		if len(csvStr) > 0 {
			csvStr += ","
		}
		if nonNumericRegexp.MatchString(col) {
			csvStr += "\"" + strings.Trim(col, " ") + "\""
		} else {
			csvStr += strings.Trim(col, " ")
		}
		from = pos
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

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide an input file which uses fixed width for columns")
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

	inputFile, err := os.Open(inFile)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer inputFile.Close()

	outputFile, err := os.Create(outFile)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer outputFile.Close()

	if strings.HasSuffix(inFile, ".json") {
		jsonBytes, err := os.ReadFile(inFile)
		if err != nil {
			fmt.Printf("Error reading %s as JSON file: %v\n", inFile, err)
			return
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
			return
		}
		csvStr := jsList2csv(jsonObject)
		_, err = io.WriteString(outputFile, csvStr)
		if err != nil {
			fmt.Printf("Error writing %s as JSON into %s file: %v\n", inFile, outputFile, err)
			return
		}
	} else {
		var positions []int = nil
		scanner := bufio.NewScanner(inputFile)
		for scanner.Scan() {
			line := scanner.Text()
			// Ignore comment lines
			if strings.HasPrefix(line, "#") {
				continue
			}
			// Assuming the first line is the header, which can be used to determine the width
			if positions == nil {
				positions = nonSpacePos(line)
			}
			csvStr := line2CSV(line, positions)
			fmt.Fprintln(outputFile, csvStr)
		}
		// Check for errors.
		if err := scanner.Err(); err != nil {
			fmt.Println(err)
			return
		}
	}
}
