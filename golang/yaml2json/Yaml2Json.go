package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/ghodss/yaml"
	"io/ioutil"
	"os"
)

func prettyBytes(strB []byte) (string, error) {
	var prettyJSON bytes.Buffer
	if err := json.Indent(&prettyJSON, strB, "", "    "); err != nil {
		return "", err
	}
	return prettyJSON.String(), nil
}

func main() {
	inFile := os.Args[1]
	outFile := os.Args[2]
	// Read the YAML file.
	yamlFile, err := ioutil.ReadFile(inFile)
	if err != nil {
		fmt.Println(err)
		return
	}

	// Convert the YAML to JSON.
	jsonB, err := yaml.YAMLToJSON(yamlFile)
	if err != nil {
		fmt.Println(err)
		return
	}
	jsonStr, err2 := prettyBytes(jsonB)
	if err2 != nil {
		fmt.Println(err2)
		return
	}

	// Write the JSON to a file.
	f, err3 := os.OpenFile(outFile, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err3 != nil {
		fmt.Println(err3)
		return
	}
	defer f.Close()
	_, err = f.WriteString(jsonStr)
	if err != nil {
		fmt.Println(err)
		return
	}
}
