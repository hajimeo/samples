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
*/
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"reflect"
	"regexp"
	"strings"
	"time"
)

// This key is not used recursively and just print the value of this key.
var JSON_SEARCH_KEY = helpers.GetEnv("JSON_SEARCH_KEY", "")
var OUTPUT_DELIMITER = helpers.GetEnv("OUTPUT_DELIMITER", ",")
var bracesRg = regexp.MustCompile(`[\[\](){}]`)

func sortByKeys(bytes []byte) ([]byte, error) {
	var ifc interface{}
	err := json.Unmarshal(bytes, &ifc)
	if err != nil {
		return nil, err
	}
	if len(JSON_SEARCH_KEY) > 0 {
		keys := strings.Split(JSON_SEARCH_KEY, ".")
		printJsonValuesByKeys(ifc, keys)
	}
	return json.Marshal(ifc)
}

func printJsonValuesByKeys(jsonObj interface{}, keys []string) {
	//fmt.Printf("DEBUG: %v\n", keys)
	maybeKey := keys[0]
	// if slice (list/array), loop to find the key
	if reflect.TypeOf(jsonObj).Kind() == reflect.Slice {
		for _, obj := range jsonObj.([]interface{}) {
			// Not accepting nested lists, so assuming it's a dict (ignoring if not dict)
			maybeMap, isDict := obj.(map[string]interface{})
			if isDict {
				printJsonValuesByKeys(maybeMap, keys)
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
				if len(keys) == 1 {
					pritnValue(value, false)
					return
				}
				// if dict and more than one key, continue to find the key
				printJsonValuesByKeys(value, keys[1:])
			}
		} else {
			// Assuming only the end of keys can be slice/list
			for i, key := range tmpKeys {
				value, ok := maybeMap[key]
				if ok {
					pritnValue(value, len(tmpKeys) > (i+1))
				}
			}
		}
		// If dict and not found, just exit
		return
	}
}

func pritnValue(value interface{}, needDelimiter bool) {
	//fmt.Printf("DEBUG: %v\n", reflect.TypeOf(value).Kind())
	if helpers.IsNumeric(value) {
		fmt.Printf("%s", value)
	} else {
		if reflect.TypeOf(value).Kind() != reflect.String {
			outBytes, _ := json.Marshal(value)
			fmt.Printf("%s", outBytes)
		} else {
			fmt.Printf("\"%s\"", value)
		}
	}
	if needDelimiter {
		fmt.Printf("%s", OUTPUT_DELIMITER)
	} else {
		fmt.Printf("\n") // TODO: this is not good if Windows
	}
}

/*
Convert [aaaa,bbb] to slice (list)
*/
func str2slice(listLikeStr string) []string {
	return strings.Split(bracesRg.ReplaceAllString(listLikeStr, ""), ",")
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

func main() {
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

	var JSON_NO_SORT = os.Getenv("JSON_NO_SORT")
	if len(JSON_NO_SORT) == 0 || (JSON_NO_SORT != "Y" && JSON_NO_SORT != "y") {
		jsonSorted, err := sortByKeys(jsonBytes)
		if err != nil {
			fmt.Println(err)
			return
		}
		jsonBytes = jsonSorted
	}

	jsonSortedPP, err := prettyBytes(jsonBytes)
	if err != nil {
		fmt.Println(err)
		return
	}

	if len(outFile) > 0 {
		f, err := os.Create(outFile)
		if err != nil {
			fmt.Println(err)
			return
		}
		defer f.Close()

		_, err2 := f.WriteString(jsonSortedPP + "\n")
		if err2 != nil {
			fmt.Println(err2)
		}
		return
	}
	// If specific keys are requested, no pretty printed JSON
	if len(JSON_SEARCH_KEY) == 0 {
		fmt.Println(jsonSortedPP)
		return
	}
}
