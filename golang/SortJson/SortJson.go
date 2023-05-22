/*
 * Sort JSON in recursively (thanks to Unmarshal)
 * @see: https://stackoverflow.com/questions/18668652/how-to-produce-json-with-sorted-keys-in-go
 */
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
)

func sortJson(bytes []byte) ([]byte, error) {
	var ifc interface{}
	err := json.Unmarshal(bytes, &ifc)
	if err != nil {
		return nil, err
	}
	return json.Marshal(ifc)
}

func prettyBytes(strB []byte) (string, error) {
	var prettyJSON bytes.Buffer
	if err := json.Indent(&prettyJSON, strB, "", "    "); err != nil {
		return "", err
	}
	return prettyJSON.String(), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide an input file which uses fixed width for columns")
		return
	}
	inFile := os.Args[1]
	outFile := ""
	if len(os.Args) > 2 {
		outFile = os.Args[2]
	}
	jsonFile, _ := os.ReadFile(inFile)
	jsonSorted, err := sortJson(jsonFile)
	if err != nil {
		fmt.Println(err)
		return
	}

	jsonSortedPP, err := prettyBytes(jsonSorted)
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
	fmt.Println(jsonSortedPP)
}
