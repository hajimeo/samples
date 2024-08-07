/*
 * Sort JSON in recursively (thanks to Unmarshal)
 * @see: https://stackoverflow.com/questions/18668652/how-to-produce-json-with-sorted-keys-in-go
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
	"time"
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
	var jsonFile []byte
	if len(os.Args) > 1 {
		inFile = os.Args[1]
		jsonFile, _ = os.ReadFile(inFile)
	} else {
		jsonFile, _ = readWithTimeout(os.Stdin, 10*time.Second)
	}
	outFile := ""
	if len(os.Args) > 2 {
		outFile = os.Args[2]
	}
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
