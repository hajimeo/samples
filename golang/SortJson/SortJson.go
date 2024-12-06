/*
Sort JSON in recursively (thanks to Unmarshal)
@see: https://stackoverflow.com/questions/18668652/how-to-produce-json-with-sorted-keys-in-go
curl -o /tmp/sortjson -L "https://github.com/hajimeo/samples/raw/master/misc/sortjson_$(uname)_$(uname -m)" && chmod a+x /tmp/sortjson

Arguments:
- If the first argument is set, it will read the file as input.
- If the second argument is set, it will write the result to the file.
- If no argument is set, it will read from stdin.

Used Environment variables:
- JSON_SEARCH_KEY: If set, it will print the value of the key. If the key is nested, use dot (.) as a separator.
- JSON_NO_SORT: If set to "Y" or "y", it will not sort the keys.
- OUTPUT_DELIMITER: Default is ","
- IS_NDJSON: Default is false. Set to "Y" or "y" if the input is NDJSON.
- JSON_ESCAPE: Convert JSON string to escaped string (e.g. " -> \")

Advanced example:

	curl -sSf "http://localhost:8081/repository/nodejs/-/v1/search?text=*a*&size=10" | JSON_SEARCH_KEY="objects.package" sortjson | IS_NDJSON="Y" OUTPUT_DELIMITER="@" JSON_SEARCH_KEY="name,version" sortjson
*/
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/hajimeo/samples/golang/helpers"
	"io"
	"os"
	"reflect"
	"regexp"
	"strings"
	"time"
)

// This key is not used recursively and just print the value of this key.
var JSON_SEARCH_KEY = ""
var OUTPUT_DELIMITER = ","
var NULL_VALUE = "<null>"
var LINE_BREAK = "\n"
var STRING_QUOTE = ""
var IS_NDJSON = false
var JSON_ESCAPE = false
var JSON_NO_SORT = ""
var SaveToPointer *os.File
var BracesRg = regexp.MustCompile(`[\[\](){}]`)

func sortByKeys(bytes []byte) ([]byte, error) {
	var ifc interface{}
	err := json.Unmarshal(bytes, &ifc)
	if err != nil {
		return nil, err
	}
	if len(JSON_SEARCH_KEY) > 0 {
		keys := strings.Split(JSON_SEARCH_KEY, ".")
		//fmt.Printf("DEBUG: keys = %v\n", keys)
		printJsonValuesByKeys(ifc, keys)
		return nil, nil
	}
	return json.Marshal(ifc)
}

func printJsonValuesByKeys(jsonObj interface{}, searchKeys []string) {
	//fmt.Printf("DEBUG: searchKeys = %v\n", searchKeys)
	maybeKey := searchKeys[0]
	// if slice (list/array), loop to find the key
	if reflect.TypeOf(jsonObj).Kind() == reflect.Slice {
		for _, obj := range jsonObj.([]interface{}) {
			// Not accepting nested lists, so assuming it's a dict (ignoring if not dict)
			maybeMap, isDict := obj.(map[string]interface{})
			if isDict {
				printJsonValuesByKeys(maybeMap, searchKeys)
			}
		}
		return
	}
	maybeMap, isDict := jsonObj.(map[string]interface{})
	if isDict {
		tmpKeys := str2slice(maybeKey)
		if len(tmpKeys) == 1 {
			value, ok := maybeMap[tmpKeys[0]]
			if ok {
				// if dict and only one key, print and exit
				if len(searchKeys) == 1 {
					printValue(value, false)
					return
				}
				// if dict and more than one key, continue to find the key
				printJsonValuesByKeys(value, searchKeys[1:])
			}
		} else {
			// Assuming only the end of searchKeys can be a slice/list
			for i, key := range tmpKeys {
				value, ok := maybeMap[key]
				if ok {
					printValue(value, len(tmpKeys) > (i+1))
				}
			}
		}
		// If dict and not found, just exit
		return
	}
}

func printfOrSave(line string) (n int, err error) {
	// At this moment, excluding empty line
	if len(line) == 0 {
		return
	}
	if SaveToPointer != nil {
		return fmt.Fprint(SaveToPointer, line)
	}
	return fmt.Printf(line)
}

func printValue(value interface{}, needDelimiter bool) {
	//fmt.Printf("DEBUG: %v\n", value)
	//fmt.Printf("DEBUG: kind = %v\n", reflect.TypeOf(value).Kind())	// if nil, this causes SIGSEGV
	if value == nil {
		printfOrSave(fmt.Sprintf("%s", NULL_VALUE))
	} else if helpers.IsNumeric(value) {
		printfOrSave(fmt.Sprintf("%v", value))
	} else {
		if reflect.TypeOf(value).Kind() != reflect.String {
			outBytes, _ := json.Marshal(value)
			printfOrSave(fmt.Sprintf("%s", outBytes))
		} else {
			printfOrSave(fmt.Sprintf("%s%s%s", STRING_QUOTE, value, STRING_QUOTE))
		}
	}
	if needDelimiter {
		printfOrSave(fmt.Sprintf("%s", OUTPUT_DELIMITER))
	} else {
		printfOrSave(fmt.Sprintf(LINE_BREAK))
	}
}

/*
Convert [aaaa,bbb] to slice (list)
*/
func str2slice(listLikeStr string) []string {
	return strings.Split(BracesRg.ReplaceAllString(listLikeStr, ""), ",")
	/*
		var result []string
		err := json.Unmarshal([]byte(listLikeStr), &result)
		if err != nil {
			result = append(result, listLikeStr)
		}
		return result
	*/
}

func prettyBytes(strB []byte) (string, error) {
	if len(strB) == 0 {
		return "", nil
	}
	var prettyJSON bytes.Buffer
	if err := json.Indent(&prettyJSON, strB, "", "    "); err != nil {
		return "", err
	}
	return prettyJSON.String(), nil
}

// AI generated :-)
func readWithTimeout(r io.Reader, timeout time.Duration) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	reader := bufio.NewReader(r)
	done := make(chan []byte)
	errCh := make(chan error)

	go func() {
		data, err := io.ReadAll(reader)
		if err != nil {
			errCh <- err
			return
		}
		done <- data
	}()

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case data := <-done:
		return data, nil
	case err := <-errCh:
		return nil, err
	}
}

func setGlobals() {
	JSON_SEARCH_KEY = helpers.GetEnv("JSON_SEARCH_KEY", JSON_SEARCH_KEY)
	IS_NDJSON = helpers.GetEnvBool("IS_NDJSON", false)
	JSON_ESCAPE = helpers.GetEnvBool("JSON_ESCAPE", false)
	JSON_NO_SORT = helpers.GetEnv("JSON_NO_SORT", JSON_NO_SORT)
	OUTPUT_DELIMITER = helpers.GetEnv("OUTPUT_DELIMITER", OUTPUT_DELIMITER)
	NULL_VALUE = helpers.GetEnv("NULL_VALUE", NULL_VALUE)
	LINE_BREAK = helpers.GetEnv("LINE_BREAK", LINE_BREAK)
	STRING_QUOTE = helpers.GetEnv("STRING_QUOTE", STRING_QUOTE)
}

func processOneJson(jsonBytes []byte, outFile string) {
	if len(JSON_NO_SORT) == 0 || (JSON_NO_SORT != "Y" && JSON_NO_SORT != "y") {
		jsonSorted, err := sortByKeys(jsonBytes)
		if err != nil {
			fmt.Println(err)
			return
		}
		jsonBytes = jsonSorted
	}

	var jsonSortedPP string
	var err error
	if JSON_ESCAPE {
		jsonSortedPP = string(jsonBytes)
		// Somehow jsonEscape is not available, so manually escaping
		jsonSortedPP = strings.ReplaceAll(jsonSortedPP, `"`, `\"`)
		jsonSortedPP = strings.ReplaceAll(jsonSortedPP, "\t", `\\t"`)
		jsonSortedPP = strings.ReplaceAll(jsonSortedPP, "\n", `\\n`)
		// TODO: add more as per https://www.freeformatter.com/json-escape.html
		//       Implement same as 'import sys,json;print(json.dumps(open('${_script_file}').read()))'
	} else {
		jsonSortedPP, err = prettyBytes(jsonBytes)
		if err != nil {
			fmt.Println(err)
			return
		}
	}

	if len(outFile) > 0 && len(jsonSortedPP) > 0 {
		_, err2 := SaveToPointer.WriteString(jsonSortedPP + LINE_BREAK)
		if err2 != nil {
			fmt.Println(err2)
		}
		return
	}

	// If specific search keys (JSON_SEARCH_KEY) are requested, jsonSortedPP should be empty
	if len(jsonSortedPP) > 0 {
		fmt.Println(jsonSortedPP)
	}
	return
}

func main() {
	setGlobals()

	inFile := ""
	var jsonBytes []byte
	if len(os.Args) > 1 {
		inFile = os.Args[1]
		jsonBytes, _ = os.ReadFile(inFile)
	} else {
		jsonBytes, _ = readWithTimeout(os.Stdin, 10*time.Second)
	}
	outFile := ""
	if len(os.Args) > 2 {
		outFile = os.Args[2]
	}
	if len(outFile) > 0 {
		var err error
		SaveToPointer, err = os.Create(outFile)
		if err != nil {
			fmt.Println(err)
			return
		}
		defer SaveToPointer.Close()
	}

	if IS_NDJSON {
		// Split by line
		lines := strings.Split(string(jsonBytes), LINE_BREAK)
		for _, line := range lines {
			if len(line) == 0 {
				continue
			}
			processOneJson([]byte(line), outFile)
		}
	} else {
		processOneJson(jsonBytes, outFile)
	}
}
