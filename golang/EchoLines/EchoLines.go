package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"regexp"
	"strconv"
)

func usage() {
	fmt.Println(`
Read one file and output only necessary lines.

# To install:
curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/gonetstat_$(uname)_$(uname -m)
chmod a+x /usr/local/bin/echolines

# How to use:
echolines some_file from_regex [end_regex] [exclude_regex] [how_many]

echolines wrapper_concat.log "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "^  class space" > threads.txt

END`)
}

func main() {
	var fromRegex *regexp.Regexp
	var endRegex *regexp.Regexp
	var excRegex *regexp.Regexp
	var howMany = 0

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
		howMany, _ = strconv.Atoi(os.Args[5])
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	foundFromLine := false
	foundHowMany := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !foundFromLine && fromRegex != nil && fromRegex.MatchString(line) {
			foundFromLine = true
			foundHowMany++
			fmt.Println(scanner.Text())
			continue
		}

		if foundFromLine && endRegex != nil && endRegex.MatchString(line) {
			foundFromLine = false
			fmt.Println(scanner.Text())
			if howMany > 0 && foundHowMany >= howMany {
				break
			}
			continue
		}

		if !foundFromLine {
			continue
		}
		if excRegex != nil && excRegex.MatchString(line) {
			continue
		}
		fmt.Println(scanner.Text())
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}
}
