package main

import (
	"bufio"
	"fmt"
	"html"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

var _DEBUG = ""

func usage() {
	fmt.Println(`
Read one file and output only necessary lines.

# TO INSTALL:
	curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/echolines_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/echolines

# HOW TO USE:
	echolines some_file1,some_file2 FROM_REGEXP [END_REGEXP] [file_prefix]

NOTE: If no capture group is used in the END_REGEXP, the end line is not echoed.

## NXRM2 thread dumps
	echolines "wrapper.log.2,wrapper.log.1,wrapper.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" > threads.txt

## NXRM3 thread dumps
	cat "./jvm.log" | echolines "" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" "thread_"

## Get duration of query
	cat ./nexus.log | ELAPSED_REGEX="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d)" echolines "" "Preparing:" "Total:"

# ENV VARIABLES:
	HTML_REMOVE=Y
		Remove all HTML tags and convert HTML entities
	INCL_REGEX=<some regex strings>
		If regular expression is specified, only matching lines are included.
	EXCL_REGEX=<some regex strings>
		If regular expression is specified, matching lines are excluded.
	ELAPSED_REGEX=<some datetime like regex string>
		If provided, calculate the duration between FROM_REGEX matching line and END_REGEXP (or next FROM_REGEX) line
	ELAPSED_FORMAT=<golang time library acceptable string>
		Default is "2006-01-02 15:04:05,000" @see: https://pkg.go.dev/time
END`)
}

var FROM_REGEXP *regexp.Regexp
var END_REGEXP *regexp.Regexp
var INCL_REGEX = os.Getenv("INCL_REGEX")
var INCL_REGEXP *regexp.Regexp
var EXCL_REGEX = os.Getenv("EXCL_REGEX")
var EXCL_REGEXP *regexp.Regexp
var ELAPSED_REGEX = os.Getenv("ELAPSED_REGEX")
var ELAPSED_REGEXP *regexp.Regexp
var ELAPSED_FORMAT = os.Getenv("ELAPSED_FORMAT")
var FROM_DATETIME_STR = ""
var HTML_REMOVE = os.Getenv("HTML_REMOVE")
var TAG_REGEXP = regexp.MustCompile(`<[^>]+>`)
var IN_FILES []string
var OUT_PREFIX = ""
var OUT_FILE *os.File
var FOUND_FROM_LINE = false
var FOUND_COUNT = 0

func echoLine(line string, f *os.File) {
	if len(HTML_REMOVE) > 0 {
		line = removeHTML(line)
	}
	if f == nil {
		fmt.Println(line)
		return
	}
	byteLen, err := f.WriteString(line + "\n")
	if byteLen < 0 || err != nil {
		log.Fatal(err)
	}
}

func processFile(inFile *os.File) {
	scanner := bufio.NewScanner(inFile)
	var err error
	for scanner.Scan() {
		line := scanner.Text()

		if !FOUND_FROM_LINE && FROM_REGEXP != nil && FROM_REGEXP.MatchString(line) {
			FOUND_FROM_LINE = true
			FOUND_COUNT++

			if len(OUT_PREFIX) > 0 {
				outFilePath := fmt.Sprintf("%s%d", OUT_PREFIX, FOUND_COUNT)
				if _, err := os.Stat(outFilePath); err == nil {
					_, _ = fmt.Fprintf(os.Stderr, "[ERROR] %s exists.\n", outFilePath)
					return
				}
				if OUT_FILE != nil {
					_ = OUT_FILE.Close()
				}
				OUT_FILE, err = os.OpenFile(outFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
				if err != nil {
					log.Fatal(err)
				}
			}

			if ELAPSED_REGEXP != nil {
				elapsedStartMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
				if len(elapsedStartMatches) > 0 {
					_dlog(elapsedStartMatches)
					FROM_DATETIME_STR = elapsedStartMatches[0]
				}
			}

			echoLine(line, OUT_FILE)
			continue
		}

		if FOUND_FROM_LINE && END_REGEXP != nil {
			matches := END_REGEXP.FindStringSubmatch(line)
			if len(matches) > 0 {
				_dlog(matches)
				FOUND_FROM_LINE = false

				if ELAPSED_REGEXP != nil {
					elapsedEndMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
					if len(elapsedEndMatches) > 0 {
						_dlog(elapsedEndMatches)
						_ = timeStrDuration(FROM_DATETIME_STR, elapsedEndMatches[0], true)
					}
				}

				if len(matches) > 1 {
					echoLine(strings.Join(matches[1:], ""), OUT_FILE)
				}
				if OUT_FILE != nil {
					_ = OUT_FILE.Close()
					OUT_FILE = nil
				}
				continue
			}
		}

		if !FOUND_FROM_LINE {
			continue
		}
		if INCL_REGEXP != nil && !INCL_REGEXP.MatchString(line) {
			continue
		}
		if EXCL_REGEXP != nil && EXCL_REGEXP.MatchString(line) {
			continue
		}
		echoLine(line, OUT_FILE)
	}
}

func timeStrDuration(startTime string, endTime string, printLine bool) time.Duration {
	start, err := time.Parse(ELAPSED_FORMAT, startTime)
	if err != nil {
		fmt.Println(err)
	}
	end := time.Now()
	if len(endTime) > 0 {
		end, err = time.Parse(ELAPSED_FORMAT, endTime)
		if err != nil {
			fmt.Println(err)
		}
	}
	duration := end.Sub(start)
	if printLine {
		fmt.Printf("# start:%s, end:%s, ms:%d\n", startTime, endTime, duration.Milliseconds())
	}
	return duration
}
func removeHTML(line string) string {
	return html.UnescapeString(TAG_REGEXP.ReplaceAllString(line, ``))
}

func _dlog(message interface{}) {
	if len(_DEBUG) > 0 {
		_, _ = fmt.Fprintf(os.Stderr, "[DEBUG] %v\n", message)
	}
}

func main() {
	_DEBUG = os.Getenv("_DEBUG")
	_dlog(_DEBUG)

	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		return
	}

	if len(os.Args) > 1 && len(os.Args[1]) > 0 {
		IN_FILES = strings.Split(os.Args[1], ",")
	}
	if len(os.Args) > 2 && len(os.Args[2]) > 0 {
		FROM_REGEXP = regexp.MustCompile(os.Args[2])
	}
	if len(os.Args) > 3 && len(os.Args[3]) > 0 {
		END_REGEXP = regexp.MustCompile(os.Args[3])
	}
	if len(os.Args) > 4 && len(os.Args[4]) > 0 {
		OUT_PREFIX = os.Args[5]
	}

	if len(INCL_REGEX) > 0 {
		INCL_REGEXP = regexp.MustCompile(INCL_REGEX)
	}

	if len(EXCL_REGEX) > 0 {
		EXCL_REGEXP = regexp.MustCompile(EXCL_REGEX)
	}

	if len(ELAPSED_REGEX) > 0 {
		ELAPSED_REGEXP = regexp.MustCompile(ELAPSED_REGEX)
		if len(ELAPSED_FORMAT) == 0 {
			ELAPSED_FORMAT = "2006-01-02 15:04:05,000"
		}
	}

	if IN_FILES == nil || len(IN_FILES) == 0 {
		processFile(os.Stdin)
	} else {
		for _, path := range IN_FILES {
			inFile, err := os.Open(path)
			if err != nil {
				log.Fatal(err)
			}
			//defer inFile.Close()
			processFile(inFile)
			if inFile != nil {
				_ = inFile.Close()
			}
		}
	}

	if OUT_FILE != nil {
		_ = OUT_FILE.Close()
		OUT_FILE = nil
	}
}
