package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"xmltodict"
)

func main() {
	// Get the file name from the command line arguments.
	filename := os.Args[1]

	// Read the file contents.
	fileContents, err := os.ReadFile(filename)
	if err != nil {
		fmt.Println(err)
		return
	}

	// Parse the XML file into a map[string]interface{}.
	xmlMap, err := xmltodict.NewDecoder(bytes.NewReader(fileContents)).Decode()
	if err != nil {
		fmt.Println(err)
		return
	}

	// Convert the map[string]interface{} to JSON.
	jsonData, err := json.MarshalIndent(xmlMap, "", "  ")
	if err != nil {
		fmt.Println(err)
		return
	}

	// Print the JSON data.
	fmt.Println(string(jsonData))
}
