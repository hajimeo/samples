package main

import (
	"encoding/json"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: validate-on /path/to/file.json")
		os.Exit(0)
	}
	_debug := false
	if len(os.Args) >= 3 {
		_debug = os.Args[2] == "debug"
	}
	filePath := os.Args[1]
	data, err := os.ReadFile(filePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: reading file %s: %v\n", filePath, err)
		os.Exit(1) // Exit with a non-zero status code for invalid files
	}

	if json.Valid(data) {
		if _debug {
			fmt.Fprintf(os.Stderr, "DEBUG: %s is a valid JSON file.\n", filePath)
		}
	} else {
		fmt.Fprintf(os.Stderr, "ERROR: %s contains invalid JSON.\n", filePath)
		os.Exit(1)
	}
}
