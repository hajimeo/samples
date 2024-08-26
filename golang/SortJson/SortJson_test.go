package main

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestSortByKeys_ValidJson(t *testing.T) {
	input := []byte(`{"b":2,"a":1}`)
	expected := []byte(`{"a":1,"b":2}`)
	result, err := sortByKeys(input)
	assert.NoError(t, err)
	assert.JSONEq(t, string(expected), string(result))
}

func TestSortByKeys_InvalidJson(t *testing.T) {
	input := []byte(`{"b":2,"a":1`)
	_, err := sortByKeys(input)
	assert.Error(t, err)
}

func TestPrintJsonValuesByKeys_SingleKey(t *testing.T) {
	jsonBytes, _ := os.ReadFile("./tests/resources/test.json")
	var jsonObj interface{}
	json.Unmarshal(jsonBytes, &jsonObj)
	keys := strings.Split("continuationToken", ".")
	printJsonValuesByKeys(jsonObj, keys)
	// Check output if necessary
	//t.Logf("Log = %s", output)
	//assert.Equal(t, NULL_VALUE+"\n", output)
}

func TestPrintJsonValuesByKeys_NestedKey(t *testing.T) {
	//os.Setenv("STRING_QUOTE", "\"")
	jsonBytes, _ := os.ReadFile("./tests/resources/test.json")
	var jsonObj interface{}
	json.Unmarshal(jsonBytes, &jsonObj)
	keys := strings.Split("items.[name,currentState]", ".")
	printJsonValuesByKeys(jsonObj, keys)
	// Check output if necessary
	//assert.Contains(t, output, "Cleanup unused nuget blobs from nexus")
	//t.Logf("%s", output)
	//os.Unsetenv("STRING_QUOTE")
}

func TestStr2Slice_ValidString(t *testing.T) {
	input := "[aaaa,bbb]"
	expected := []string{"aaaa", "bbb"}
	result := str2slice(input)
	assert.Equal(t, expected, result)
}

func TestPrettyBytes_ValidJson(t *testing.T) {
	input := []byte(`{"a":1,"b":2}`)
	expected := `{
    "a": 1,
    "b": 2
}`
	result, err := prettyBytes(input)
	assert.NoError(t, err)
	assert.Equal(t, expected, result)
}

func TestReadWithTimeout_ValidInput(t *testing.T) {
	input := bytes.NewBufferString("test input")
	result, err := readWithTimeout(input, 1*time.Second)
	assert.NoError(t, err)
	assert.Equal(t, []byte("test input"), result)
}

func TestReadWithTimeout_Timeout(t *testing.T) {
	input := bytes.NewBufferString("test input")
	result, err := readWithTimeout(input, 1*time.Nanosecond)
	assert.Error(t, err)
	assert.Nil(t, result)
}

func TestMain_ReadFromFile(t *testing.T) {
	os.Args = []string{"cmd", "testdata/input.json"}
	main()
	// Check output if necessary
}

func TestMain_ReadFromStdin(t *testing.T) {
	os.Args = []string{"cmd"}
	// Simulate stdin input if necessary
	main()
	// Check output if necessary
}

func TestMain_WriteToFile(t *testing.T) {
	os.Args = []string{"cmd", "testdata/input.json", "testdata/output.json"}
	main()
	// Check output file if necessary
}

func TestMain_NoSort(t *testing.T) {
	os.Setenv("JSON_NO_SORT", "Y")
	os.Args = []string{"cmd", "testdata/input.json"}
	main()
	// Check output if necessary
	os.Unsetenv("JSON_NO_SORT")
}

func TestMain_SearchKey(t *testing.T) {
	os.Setenv("JSON_SEARCH_KEY", "a.b")
	os.Args = []string{"cmd", "testdata/input.json"}
	main()
	// Check output if necessary
	os.Unsetenv("JSON_SEARCH_KEY")
}
