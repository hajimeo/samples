package main

import (
	"github.com/stretchr/testify/assert"
	"os"
	"testing"
)

var LINE = "  Block                                                                                                                                                                                                                                                                                                                                          Invocations  SelfTime.Total  SelfTime.Avg  SelfTime.Min  SelfTime.Max  WallTime.Total  WallTime.Avg  WallTime.Min  WallTime.Max"

func TestNonSpacePos(t *testing.T) {
	//words := strings.Fields(LINE)
	//t.Logf("%v", words)
	//i := strings.Index(LINE, "Block")
	//t.Logf("%v", LINE[0:i])

	positions := nonSpacePos(LINE)
	if positions == nil || len(positions) == 0 {
		t.Errorf("positions from nonSpacePos is empty")
	}
	t.Logf("%v", positions)
}

func TestLine2CSV(t *testing.T) {
	positions := nonSpacePos(LINE)
	csvStr := line2CSV(LINE, positions)
	if len(csvStr) == 0 {
		t.Errorf("csvStr from line2CSV is empty")
	}
	t.Logf("%v", csvStr)
}

func TestProcessJson_InvalidJsonFile_ReturnsError(t *testing.T) {
	// TODO: need more tests
	inFile := "testdata/invalid.json"
	outFile, _ := os.CreateTemp("", "output.csv")
	defer os.Remove(outFile.Name())
	jsonKey := ""

	result := processJson(inFile, outFile, jsonKey)
	//contents, err := os.ReadFile(outFile.Name())
	assert.Equal(t, false, result)
}

func TestProcessFile_ValidFixedWidthFile_WritesCsv(t *testing.T) {
	inFile := "testdata/invalid.log"
	//inFile := "/Volumes/Samsung_T5/hajime/cases/97139/support-20241105-144306-2/log/request.log"
	outFile, _ := os.CreateTemp("", "output.csv")
	defer os.Remove(outFile.Name())
	lineRegex := `(\S+) (\S+) (\S+) \[([^\]]+)\] "([^"]+)" (\S+) (\S+) (\S+) (\S+) "([^"]+)" \[([^\]]+)\]`
	result := processFile(inFile, outFile, lineRegex)
	//_, err := os.ReadFile(outFile.Name())
	assert.Equal(t, false, result)
}
