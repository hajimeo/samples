/*
Sort JSON in recursively (thanks to Unmarshal)
@see: https://stackoverflow.com/questions/18668652/how-to-produce-json-with-sorted-keys-in-go
curl -o /tmp/sortjson -L "https://github.com/hajimeo/samples/raw/master/misc/sortjson_$(uname)_$(uname -m)" && chmod a+x /tmp/sortjson
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
	"strings"
	"time"
)

// This key is not used recursively and just print the value of this key.
var JSON_SEARCH_KEY = os.Getenv("JSON_SEARCH_KEY")

func sortJson(bytes []byte) ([]byte, error) {
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
	key := keys[0]
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
		value, ok := maybeMap[key]
		if ok {
			// if dict and only one key, print and exit
			if len(keys) == 1 {
				//fmt.Printf("DEBUG: %v\n", reflect.TypeOf(value).Kind())
				out := value
				if reflect.TypeOf(value).Kind() != reflect.String {
					out, _ = json.Marshal(value)
				}
				fmt.Printf("%s\n", out)
				return
			}
			// if dict and more than one key, continue to find the key
			printJsonValuesByKeys(value, keys[1:])
		}
		// If dict and not found, just exit
		return
	}
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
		jsonSorted, err := sortJson(jsonBytes)
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
	if len(JSON_SEARCH_KEY) == 0 {
		fmt.Println(jsonSortedPP)
		return
	}
}
