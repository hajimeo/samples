package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
)

var _DEBUG = ""

func usage() {
	fmt.Println(`
Read one file and output only necessary lines.

# To install:
curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/gonetstat_$(uname)_$(uname -m)
chmod a+x /usr/local/bin/echolines

# How to use:
echolines some_file from_regex [end_regex] [exclude_regex] [file_prefix]

echolines wrapper_concat.log "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" > threads.txt

NOTE: if no capture group is used in the end_regex, the end line is not echoed.

END`)
}

// TODO: this is probably slow
func echoLine(line string, path string) {
	if len(path) == 0 {
		fmt.Println(line)
		return
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	byteLen, err := f.WriteString(line + "\n")
	if byteLen < 0 || err != nil {
		log.Fatal(err)
	}
}

func _dlog(message interface{}) {
	if len(_DEBUG) > 0 {
		fmt.Fprintf(os.Stderr, "[DEBUG] %v\n", message)
	}
}

func main() {
	_DEBUG = os.Getenv("_DEBUG")
	_dlog(_DEBUG)

	var fromRegex *regexp.Regexp
	var endRegex *regexp.Regexp
	var excRegex *regexp.Regexp
	var filesPrefix = ""

	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		return
	}

	if len(os.Args) > 2 && len(os.Args[2]) > 0 {
		fromRegex = regexp.MustCompile(os.Args[2])
	}
	if len(os.Args) > 3 && len(os.Args[3]) > 0 {
		endRegex = regexp.MustCompile(os.Args[3])
	}
	if len(os.Args) > 4 && len(os.Args[4]) > 0 {
		excRegex = regexp.MustCompile(os.Args[4])
	}
	if len(os.Args) > 5 && len(os.Args[5]) > 0 {
		filesPrefix = os.Args[5]
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	foundFromLine := false
	foundHowMany := 0
	filePath := ""
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()

		if !foundFromLine && fromRegex != nil && fromRegex.MatchString(line) {
			foundFromLine = true
			foundHowMany++
			if len(filesPrefix) > 0 {
				filePath = fmt.Sprintf("%s%d", filesPrefix, foundHowMany)
				if _, err := os.Stat(filePath); err == nil {
					fmt.Printf("[WARN] %s exists.\n", filePath)
					return
				}
			}
			echoLine(scanner.Text(), filePath)
			continue
		}

		if foundFromLine && endRegex != nil {
			matches := endRegex.FindStringSubmatch(line)
			if len(matches) > 0 {
				_dlog(matches)
				foundFromLine = false
				if len(matches) > 1 {
					echoLine(strings.Join(matches[1:], ""), filePath)
				}
				continue
			}
		}

		if !foundFromLine {
			continue
		}
		if excRegex != nil && excRegex.MatchString(line) {
			continue
		}
		echoLine(scanner.Text(), filePath)
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}
}
