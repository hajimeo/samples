package main

import (
	"bufio"
	"fmt"
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

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide an input file which uses fixed width for columns")
		return
	}
	inFile := os.Args[1]
	outFile := inFile + ".csv"
	if len(os.Args) > 2 {
		outFile = os.Args[2]
	}
	var positions []int = nil

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
