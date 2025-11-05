package main

import (
	"bufio"
	"fmt"
	"os"
	"sync"
)

func main() {
	// Create a channel to receive the contents of the files.
	fileContents := make(chan string, 1000)

	// Create a goroutine for each file that you want to read.
	var wg sync.WaitGroup
	for _, file := range os.Args[1:] {
		wg.Add(1)
		go readFile(file, fileContents, &wg)
	}

	// Close the channel when all of the goroutines are finished.
	go func() {
		wg.Wait()
		close(fileContents)
	}()

	// Read the contents of the channel and do whatever you need to do with them.
	for contents := range fileContents {
		fmt.Println(contents)
	}
}

func readFile(filename string, contents chan string, wg *sync.WaitGroup) {
	// Open the file.
	file, err := os.Open(filename)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer file.Close()

	// Read the contents of the file line by line.
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		contents <- scanner.Text()
	}

	// Signal that the goroutine is finished.
	wg.Done()
}
