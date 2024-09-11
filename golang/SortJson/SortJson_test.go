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

func TestSortByKeys_WithJsonSearchKey(t *testing.T) {
	os.Setenv("JSON_SEARCH_KEY", "a,c")
	input := []byte(`{"b":2,"a":1,"c":3}`)
	// JSON_SEARCH_KEY is for just printing the value of the key, so expected is same
	setGlobals()
	result, err := sortByKeys(input)
	os.Unsetenv("JSON_SEARCH_KEY")
	assert.NoError(t, err)
	assert.Equal(t, "", string(result))
	t.Logf("Check output if necessary. Should be '1,3'")
}

func TestPrintJsonValuesByKeys_SingleKey(t *testing.T) {
	jsonBytes, _ := os.ReadFile("./tests/resources/test.json")
	var jsonObj interface{}
	json.Unmarshal(jsonBytes, &jsonObj)
	keys := strings.Split("continuationToken", ".")
	printJsonValuesByKeys(jsonObj, keys)
	t.Logf("Check output if necessary")
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

func TestMain_WriteToFile(t *testing.T) {
	os.Args = []string{"cmd", "./tests/resources/test.json", "/tmp/output.json"}
	os.Unsetenv("JSON_SEARCH_KEY")
	main()
	t.Logf("Check output if necessary: /tmp/output.json")
	//output, _ := os.ReadFile("/tmp/output.json")
	//assert.Contains(t, string(output), "Cleanup unused nuget blobs from nexus")
}

func TestMain_NoSort(t *testing.T) {
	os.Setenv("JSON_NO_SORT", "Y")
	os.Args = []string{"cmd", "./tests/resources/test.json", "/tmp/output_nosort.json"}
	main()
	os.Unsetenv("JSON_NO_SORT")
	output, _ := os.ReadFile("/tmp/output_nosort.json")
	assert.Contains(t, string(output), "Cleanup unused nuget blobs from nexus")
}

func TestMain_SearchKey(t *testing.T) {
	os.Setenv("JSON_SEARCH_KEY", "items.[name,currentState,dummyNum]")
	os.Args = []string{"cmd", "./tests/resources/test.json", "/tmp/output_withsearch.json"}
	main()
	t.Logf("Check output if necessary: /tmp/output_withsearch.json")
	// Check output if necessary
	os.Unsetenv("JSON_SEARCH_KEY")
}
