package main

import (
	"bufio"
	"fmt"
	"html"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

func usage() {
	fmt.Println(`
Read one file and output only necessary lines.

# TO INSTALL:
	curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/echolines_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/echolines

# HOW TO USE:
	echolines [some_file1,some_file2] FROM_REGEXP [END_REGEXP] [OUT_DIR]

## NOTE:
If END_REGEXP is provided but without any capture group, the end line is not echoed (not included).
If the first argument is empty, the script accepts the STDIN.

### NXRM2 thread dumps:
	echolines "wrapper.log.2,wrapper.log.1,wrapper.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" > threads.txt
### NXRM3 thread dumps:
	echolines "./jvm.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" "_threads"
### NXRM3 thread dump split per thread:
	SPLIT_FILE=Y echolines "./info/threads.txt" "^\".+" "" "_threads"

### Get duration of each line:
	cat ./nexus.log | ELAPSED_REGEX="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d)" echolines "" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d"
### Get duration of NXRM3 queries:
	cat ./nexus.log | ELAPSED_REGEX="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d)" echolines "" "Preparing:" "(^.+Total:.+)"

# ENV VARIABLES:
	SPLIT_FILE=Y
		Save the result into multiple files (if OUT_DIR is given, this becomes Y automatically)
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

var _DEBUG = os.Getenv("_DEBUG")
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
var SPLIT_FILE = os.Getenv("SPLIT_FILE")
var REM_CHAR_REGEXP = regexp.MustCompile(`[/\\?%*:|"<>@={}() ]`)
var REM_CHAR_REGEXP2 = regexp.MustCompile(`[_]+`)
var TAG_REGEXP = regexp.MustCompile(`<[^>]+>`)
var IN_FILES []string
var OUT_DIR = ""
var OUT_FILE *os.File
var FROM_LINE_PFX = ""
var FOUND_COUNT = 0

func echoLine(line string, f *os.File) {
	if HTML_REMOVE == "Y" {
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
		//_dlog(line)

		// Need to check the end line first, before checking from line.
		if len(FROM_LINE_PFX) > 0 && END_REGEXP != nil {
			matches := END_REGEXP.FindStringSubmatch(line)
			if len(matches) > 0 {
				FROM_LINE_PFX = ""

				// If regex group is used, including that matching characters into current output.
				if len(matches) > 1 {
					echoLine(strings.Join(matches[1:], ""), OUT_FILE)
				}

				// If asked to split into multiple files, closing current out file.
				if OUT_FILE != nil {
					_ = OUT_FILE.Close()
					OUT_FILE = nil
				}

				// If asked to output the elapsed time (duration), processing after outputting the end line.
				if ELAPSED_REGEXP != nil {
					elapsedEndMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
					if len(elapsedEndMatches) > 0 {
						_dlog(elapsedEndMatches)
						_ = timeStrDuration(FROM_DATETIME_STR, elapsedEndMatches[0], true)
					}
				}

				// Already outputted the end line, so no need to process this line
				if len(matches) > 1 {
					_dlog(strconv.Itoa(FOUND_COUNT) + " end line echoed")
					continue
				}
			}
		}

		if len(FROM_LINE_PFX) == 0 && FROM_REGEXP != nil {
			matches := FROM_REGEXP.FindStringSubmatch(line)
			if len(matches) > 0 {
				FOUND_COUNT++
				// echo "${_prev_str}" | sed "s/[ =]/_/g" | tr -cd '[:alnum:]._-\n' | cut -c1-192
				FROM_LINE_PFX = REM_CHAR_REGEXP.ReplaceAllString(matches[0], "_")
				FROM_LINE_PFX = REM_CHAR_REGEXP2.ReplaceAllString(FROM_LINE_PFX, "_")
				if len(FROM_LINE_PFX) > 192 {
					_dlog("Truncated " + FROM_LINE_PFX)
					FROM_LINE_PFX = FROM_LINE_PFX[:192]
				} else {
					_dlog(FROM_LINE_PFX)
				}

				if SPLIT_FILE == "Y" {
					outFilePath := filepath.Join(OUT_DIR, strconv.Itoa(FOUND_COUNT)+"_"+FROM_LINE_PFX+".out")
					if _, err := os.Stat(outFilePath); err == nil {
						_, _ = fmt.Fprintf(os.Stderr, "[ERROR] %s exists.\n", outFilePath)
						return
					}
					// If previous file is still open, close it
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
				_dlog(strconv.Itoa(FOUND_COUNT) + " from line echoed")
				continue
			}
		}

		// not found the from line yet
		if len(FROM_LINE_PFX) == 0 {
			_dlog(strconv.Itoa(FOUND_COUNT) + " No FROM_LINE_PFX")
			continue
		}
		if INCL_REGEXP != nil && !INCL_REGEXP.MatchString(line) {
			_dlog("Did not match with INCL_REGEX:" + INCL_REGEX)
			continue
		}
		if EXCL_REGEXP != nil && EXCL_REGEXP.MatchString(line) {
			_dlog("Matched with EXCL_REGEX:" + EXCL_REGEX)
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
		// As "sec,ms" contains comma, using "|". Also "<num> ms" for easier sorting (it was "ms:<num>")
		fmt.Printf("# start:%s | end:%s | %d ms\n", startTime, endTime, duration.Milliseconds())
	}
	return duration
}
func removeHTML(line string) string {
	return html.UnescapeString(TAG_REGEXP.ReplaceAllString(line, ``))
}

func _dlog(message interface{}) {
	if _DEBUG == "Y" {
		_, _ = fmt.Fprintf(os.Stderr, "[DEBUG] %v\n", message)
	}
}

func main() {
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
	} else if len(os.Args) >= 2 && len(os.Args[3]) == 0 {
		END_REGEXP = FROM_REGEXP
	}
	if len(os.Args) > 4 && len(os.Args[4]) > 0 {
		OUT_DIR = os.Args[4]
		SPLIT_FILE = "Y"
		_ = os.MkdirAll(OUT_DIR, os.ModePerm)
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
