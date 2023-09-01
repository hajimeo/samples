package main

import (
	"bufio"
	"fmt"
	"html"
	"log"
	"math"
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
	echolines [some_file1,some_file2] START_REGEX [END_REGEX] [OUT_DIR]

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
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	cat ./nexus.log | echolines "" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d"
### Get duration of NXRM3 queries:
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	cat ./nexus.log | echolines "" "Preparing:" "(^.+Total:.+)"
### Get duration of IQ Evaluate a File
    rg 'POST /rest/scan/.+Scheduling scan task (\S+)' -o -r '$1' log/clm-server.log | xargs -I{} rg -w "{}" ./log/clm-server.log | sort | uniq > scan_tasks.log
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	ELAPSED_KEY_REGEX="\[([^\]]+)" echolines ./scan_tasks.log "Running scan task" "(^.+Completed scan task.+)" | rg '^# s'

# ENV VARIABLES:
	SPLIT_FILE=Y
		Save the result into multiple files (if OUT_DIR is given, this becomes Y automatically)
	HTML_REMOVE=Y
		Remove all HTML tags and convert HTML entities
	INCL_REGEX=<regex string>
		If regular expression is specified, only matching lines are included.
	EXCL_REGEX=<regex string>
		If regular expression is specified, matching lines are excluded.
	ELAPSED_REGEX=<datetime capture group regex>
		If provided, calculate the duration between START_REGEX matching line and END_REGEXP (or next START_REGEX) line
		Group capture is required to capture the datetime
	ELAPSED_FORMAT=<golang time library acceptable string>
		Default is "2006-01-02 15:04:05,000" or "15:04:05,000" @see: https://pkg.go.dev/time
	ELAPSED_KEY_REGEX=<capture group regex string>
		If the log is for multithreading application, provide regex to capture thread Id (eg: "\[([^\]]+)")
	ELAPSED_DIVIDE_MS=<integer milliseconds>
		To deside the width of ascii chart
	DISABLE_ASCII=Y
		To disable ascii chart (for slightly faster processing)
END`)
}

var _DEBUG = os.Getenv("_DEBUG")
var START_REGEXP *regexp.Regexp
var END_REGEXP *regexp.Regexp
var INCL_REGEX = os.Getenv("INCL_REGEX")
var INCL_REGEXP *regexp.Regexp
var EXCL_REGEX = os.Getenv("EXCL_REGEX")
var EXCL_REGEXP *regexp.Regexp
var ELAPSED_REGEX = os.Getenv("ELAPSED_REGEX")
var ELAPSED_REGEXP *regexp.Regexp
var ELAPSED_KEY_REGEX = os.Getenv("ELAPSED_KEY_REGEX")
var NO_KEY = "no-key"
var ELAPSED_KEY_REGEXP *regexp.Regexp
var ELAPSED_FORMAT = os.Getenv("ELAPSED_FORMAT")
var HTML_REMOVE = os.Getenv("HTML_REMOVE")
var SPLIT_FILE = os.Getenv("SPLIT_FILE")
var REM_CHAR_REGEXP = regexp.MustCompile(`[/\\?%*:|"<>@={}() ]`)
var REM_CHAR_REGEXP2 = regexp.MustCompile(`[_]+`)
var TAG_REGEXP = regexp.MustCompile(`<[^>]+>`)
var IN_FILES []string
var OUT_DIR = ""
var OUT_FILE *os.File
var START_DATETIMES = make(map[string]string)
var START_LINE_PFXS = make(map[string]string)
var FIRST_START_TIME time.Time
var ELAPSED_DIVIDE_MS = os.Getenv("ELAPSED_DIVIDE_MS")
var DISABLE_ASCII = os.Getenv("DISABLE_ASCII")
var DIVIDE_MS int64 = 0
var DIVIDE_MS_DEFAULT int64 = 60000 // 1 minute
var KEY_PADDING = 0
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
		key := getKey(line)
		// Need to check the end line first, before checking the start line.
		_, ok := START_LINE_PFXS[key]
		if ok && len(START_LINE_PFXS[key]) > 0 && END_REGEXP != nil {
			matches := END_REGEXP.FindStringSubmatch(line)
			if len(matches) > 0 {
				START_LINE_PFXS[key] = ""

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
				echoDuration(line)

				// Already outputted the end line, so no need to process this line
				if len(matches) > 1 {
					_dlog(strconv.Itoa(FOUND_COUNT) + " end line echoed")
					continue
				}
			}
		}

		if len(START_LINE_PFXS[key]) == 0 && START_REGEXP != nil {
			matches := START_REGEXP.FindStringSubmatch(line)
			if len(matches) > 0 {
				FOUND_COUNT++
				// echo "${_prev_str}" | sed "s/[ =]/_/g" | tr -cd '[:alnum:]._-\n' | cut -c1-192
				START_LINE_PFXS[key] = REM_CHAR_REGEXP.ReplaceAllString(matches[len(matches)-1], "_")
				START_LINE_PFXS[key] = REM_CHAR_REGEXP2.ReplaceAllString(START_LINE_PFXS[key], "_")
				if len(START_LINE_PFXS[key]) > 192 {
					_dlog("Trimmed " + START_LINE_PFXS[key])
					START_LINE_PFXS[key] = START_LINE_PFXS[key][:192]
				} else {
					_dlog("START_LINE_PFX: " + START_LINE_PFXS[key])
				}

				if SPLIT_FILE == "Y" {
					outFilePath := filepath.Join(OUT_DIR, strconv.Itoa(FOUND_COUNT)+"_"+START_LINE_PFXS[key]+".out")
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

				findFromDatetime(line)
				echoLine(line, OUT_FILE)
				_dlog(strconv.Itoa(FOUND_COUNT) + " start lines echoed")
				continue
			}
		}

		// not found the start line yet
		if len(START_LINE_PFXS[key]) == 0 {
			_dlog(strconv.Itoa(FOUND_COUNT) + " No START_LINE_PFX")
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

func getKey(line string) string {
	if ELAPSED_KEY_REGEXP == nil {
		// no regex specified, return the default value
		return NO_KEY
	}

	elapsedKeyMatches := ELAPSED_KEY_REGEXP.FindStringSubmatch(line)
	if len(elapsedKeyMatches) > 0 {
		_dlog("elapsedKeyMatches[0] = " + elapsedKeyMatches[0])
		return elapsedKeyMatches[len(elapsedKeyMatches)-1]
	}
	// if the line doesn't have key, just empty string
	return ""
}

func findFromDatetime(line string) {
	if ELAPSED_REGEXP == nil {
		return
	}
	elapsedStartMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
	if len(elapsedStartMatches) == 0 {
		return
	}
	_dlog(elapsedStartMatches)
	elapsedStart := elapsedStartMatches[len(elapsedStartMatches)-1]
	key := getKey(line)
	if len(key) == 0 {
		// If ELAPSED_KEY_REGEX is provided, ELAPSED_REGEXP and ELAPSED_KEY_REGEXP both need to match
		return
	}
	// TODO: should care if it's already set?
	_dlog("START_DATETIMES[" + key + "] = " + elapsedStart)
	START_DATETIMES[key] = elapsedStart
}

func echoDuration(line string) {
	if ELAPSED_REGEXP == nil {
		return
	}
	elapsedEndMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
	if len(elapsedEndMatches) == 0 {
		return
	}
	_dlog(elapsedEndMatches)
	endTimeStr := elapsedEndMatches[len(elapsedEndMatches)-1]
	key := getKey(line)
	if len(key) == 0 {
		// If ELAPSED_KEY_REGEX is provided, ELAPSED_REGEXP and ELAPSED_KEY_REGEXP both need to match
		return
	}
	_dlog(elapsedEndMatches)
	startTimeStr, ok := START_DATETIMES[key]
	if ok {
		duration := calcDurationFromStrings(startTimeStr, endTimeStr)
		ascii := ""
		if DISABLE_ASCII != "Y" {
			ascii = asciiChart(startTimeStr, duration)
		}
		if key == NO_KEY {
			// As "sec,ms" contains comma, using "|". Also "<num> ms" for easier sorting (it was "ms:<num>")
			fmt.Printf("# s:%s | e:%s | %8d ms | %s\n", startTimeStr, endTimeStr, duration.Milliseconds(), ascii)
		} else {
			if KEY_PADDING == 0 {
				KEY_PADDING = 0 - (len(key) + 2)
			}
			fmt.Printf("# s:%s | e:%s | %8d ms | %*s | %s\n", startTimeStr, endTimeStr, duration.Milliseconds(), KEY_PADDING, key, ascii)
		}
	} else {
		_, _ = fmt.Fprintf(os.Stderr, "[WARN] No start datetime found for key:%s end datetime:%s.\n", key, endTimeStr)
	}
}

func asciiChart(startTimeStr string, duration time.Duration) string {
	var ascii = ""
	var duraFromFirst time.Duration
	durationMs := duration.Milliseconds()
	if durationMs < DIVIDE_MS_DEFAULT {
		return ascii
	}
	if FIRST_START_TIME.IsZero() {
		duraFromFirst = 0
	} else {
		startTime, _ := time.Parse(ELAPSED_FORMAT, startTimeStr)
		duraFromFirst = startTime.Sub(FIRST_START_TIME)
	}
	if DIVIDE_MS == 0 {
		digit := len(strconv.FormatInt(durationMs, 10)) - 2
		DIVIDE_MS = int64(math.Pow(10, float64(digit)))
	}
	if DIVIDE_MS < DIVIDE_MS_DEFAULT {
		DIVIDE_MS = DIVIDE_MS_DEFAULT
	}
	repeat := int(duraFromFirst.Milliseconds() / DIVIDE_MS)
	for i := 1; i < repeat; i++ {
		ascii += " "
	}
	repeat = int(durationMs / DIVIDE_MS)
	for i := 1; i < repeat; i++ {
		ascii += "_"
	}
	return ascii
}

func calcDurationFromStrings(startTimeStr string, endTimeStr string) time.Duration {
	endTime := time.Now()
	if len(ELAPSED_FORMAT) == 0 {
		if len(startTimeStr) > 12 {
			ELAPSED_FORMAT = "2006-01-02 15:04:05,000"
		} else {
			ELAPSED_FORMAT = "15:04:05,000"
		}
	}
	startTime, err := time.Parse(ELAPSED_FORMAT, startTimeStr)
	if err != nil {
		fmt.Println(err)
		return -1
	}
	if FIRST_START_TIME.IsZero() {
		FIRST_START_TIME = startTime
	}
	if len(endTimeStr) > 0 {
		endTime, err = time.Parse(ELAPSED_FORMAT, endTimeStr)
		if err != nil {
			fmt.Println(err)
			return -1
		}
	}
	duration := endTime.Sub(startTime)
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
		START_REGEXP = regexp.MustCompile(os.Args[2])
	}
	if len(os.Args) > 3 && len(os.Args[3]) > 0 {
		END_REGEXP = regexp.MustCompile(os.Args[3])
	} else if len(os.Args) >= 2 && len(os.Args[3]) == 0 {
		END_REGEXP = START_REGEXP
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
	}

	if len(ELAPSED_KEY_REGEX) > 0 {
		ELAPSED_KEY_REGEXP = regexp.MustCompile(ELAPSED_KEY_REGEX)
	}

	if len(ELAPSED_DIVIDE_MS) > 0 {
		DIVIDE_MS, _ = strconv.ParseInt(ELAPSED_DIVIDE_MS, 10, 64)
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
