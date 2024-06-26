package main

import (
	"bufio"
	"fmt"
	"github.com/hajimeo/samples/golang/helpers"
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

# NOTE:
	If END_REGEXP is provided but *without any capture group*, the end line is not echoed (not included).
	If the first argument is empty, the script accepts the STDIN.

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
	ASCII_DISABLED=Y
		To disable ascii chart (for slightly faster processing)
	ASCII_ROTATE_NUM=<num>
		(experimental) To make ASCII chart width shorter by rotating per <num> lines

# USAGE EXAMPLES:
## NXRM2 thread dumps:
	echolines "wrapper.log.2,wrapper.log.1,wrapper.log" "^jvm 1    \| \d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" | sed 's/^jvm 1    | //' > threads.txt
## NXRM3 thread dumps:
	HTML_REMOVE=Y echolines "./jvm.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+|^\s+Metaspace\s+.+)" "threads"
	# If would like to split per thread:
	echolines "threads.txt" "^\".+" "" "./threads_per_thread"
	find ./threads -type f -name '[0-9]*_*.out' | xargs -P3 -t -I{} bash -c '_d="$(basename "{}" ".out")";echolines "{}" "^\".+" "" "./threads_per_thread/${_d}"'

## Get duration of each line of a thread #with thread+username+classnames:
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y #ELAPSED_KEY_REGEX="\[(qtp\S+\s+\S+\s+\S+)"
	rg 'qtp1529377038-106' ./nexus.log | echolines "" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" | rg '^# ' | sort -t'|' -k3n
	#vimdiff <(rg '\d+ms|.+' -o qtp1529377038-106_admin_dur2.out) <(rg '\d+ms|.+' -o qtp1755872334-99_admin_dur2.out)
## Get duration of NXRM3 queries, and sort by the longest:
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	echolines "./log/nexus.log" "Preparing:" "(^.+Total:.+)" | rg '^# \d\d' | sort -t'|' -k3n
## Get duration of the first 30 S3 pool requests (with org.apache.http = DEBUG. This example also checks 'Connection leased'):
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[(s3-parallel-[^\]]+)"
	rg -m30 '\[s3-parallel-.+ Connection (request|leased|released):' ./log/nexus.log > connections.out
	sed -n "1,30p" connections.out | echolines "" " leased:" "(^.+ released:.+)" | rg '^# '
## Get duration of Tasks
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="Task '([^']+)'" ASCII_DISABLED=Y
	echolines "./log/nexus.log" "QuartzTaskInfo .+ -> RUNNING" "(^.+QuartzTaskInfo .+ RUNNING -> .+)" | rg '^#'
## Get duration of blob-store-group-removal-\d+ .bytes files, with ASCII
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="(blob-store-group-removal-\d+)"
	rg 'blob-store-group-removal-\d+' -m2000 nexus.log | echolines "" "Writing blob" "(^.+Finished upload to key.+)" | rg '^#' > bytes_duration_summary.tsv
## Get duration of DEBUG cooperation2.datastore.internal.CooperatingFuture
	export ELAPSED_REGEX="\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[(qtp[^\]]+)"
	rg -F '/dotenv?null' -m2000 nexus.log | echolines "" "Requesting" "(^.+Completing.+)" | rg '^#' > bytes_duration_summary.tsv

## Get duration of IQ Evaluate a File, and sort by threadId and time
	rg 'POST /rest/scan/.+Scheduling scan task (\S+)' -o -r '$1' log/clm-server.log | xargs -I{} rg -w "{}" ./log/clm-server.log | sort | uniq > scan_tasks.log
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	ELAPSED_KEY_REGEX="\[([^ \]]+)" echolines ./scan_tasks.log "Running scan task" "(^.+Completed scan task.+)" | rg '^# \d\d' | sort -t'|' -k3,3 -k1,1

## Get duration of Eclipse Memory Analyzer Tool (MAT) threads (<file-name>.threads)
	echolines ./java_pid1404494.threads "^Thread 0x\S+" "" "./threads_per_thread"

## Get duration of mvn download (need org.slf4j.simpleLogger.showDateTime=true org.slf4j.simpleLogger.dateTimeFormat=yyyy-MM-dd HH:mm:ss.SSS)
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)"
	export ELAPSED_KEY_REGEX="https?://\S+"
	ASCII_DISABLED=Y echolines ./mvn.log "Downloading from nexus: \S+" "(^.+Downloaded from nexus: \S+)"
END`)
}

var _DEBUG = helpers.GetBoolEnv("_DEBUG", false)
var START_REGEXP *regexp.Regexp
var END_REGEXP *regexp.Regexp
var INCL_REGEX = os.Getenv("INCL_REGEX")
var INCL_REGEXP *regexp.Regexp
var EXCL_REGEX = os.Getenv("EXCL_REGEX")
var EXCL_REGEXP *regexp.Regexp
var ELAPSED_REGEX = os.Getenv("ELAPSED_REGEX")
var ELAPSED_REGEXP *regexp.Regexp
var ELAPSED_KEY_REGEX = os.Getenv("ELAPSED_KEY_REGEX")
var ELAPSED_KEY_REGEXP *regexp.Regexp
var ELAPSED_FORMAT = os.Getenv("ELAPSED_FORMAT")
var ASCII_WIDTH = helpers.GetEnvInt64("ASCII_WIDTH", 100)
var ASCII_ROTATE_NUM = helpers.GetEnvInt("ASCII_ROTATE_NUM", -1)
var NO_KEY = "no-key"
var HTML_REMOVE = helpers.GetBoolEnv("HTML_REMOVE", false)
var SPLIT_FILE = helpers.GetBoolEnv("SPLIT_FILE", false)
var REM_CHAR_REGEXP = regexp.MustCompile(`[^0-9a-zA-Z_]`)
var REM_DUPE_REGEXP = regexp.MustCompile(`[_]+`)
var TAG_REGEXP = regexp.MustCompile(`<[^>]+>`)
var IN_FILES []string
var OUT_DIR = ""
var OUT_FILES = make(map[string]*os.File)
var START_DATETIMES = make(map[string]string)
var FILE_NAME_PFXS = make(map[string]string)
var FIRST_START_TIME time.Time
var ELAPSED_DIVIDE_MS = os.Getenv("ELAPSED_DIVIDE_MS")
var ASCII_DISABLED = helpers.GetBoolEnv("ASCII_DISABLED", false)
var DIVIDE_MS int64 = 0
var KEY_PADDING = 0
var FOUND_COUNT = 0

// fmt.Printf("# s:%s | e:%s | %8d ms | %*s | %s\n", startTimeStr, endTimeStr, duration.Milliseconds(), KEY_PADDING, key, ascii)
type Duration struct {
	startTimeStr string
	endTimeStr   string
	durationMs   int64
	key          string
}

var DURATIONS = make([]Duration, 0)

func echoLine(line string, f *os.File) bool {
	if HTML_REMOVE {
		line = removeHTML(line)
	}
	if f == nil {
		fmt.Println(line)
		return true
	}
	byteLen, err := f.WriteString(line + "\n")
	helpers.PanicIfErr(err)
	if byteLen <= 0 {
		helpers.Log("INFO", "0 byte was written into "+f.Name())
	}
	return true
}

func processFile(inFile *os.File) {
	scanner := bufio.NewScanner(inFile)
	for scanner.Scan() {
		line := scanner.Text()
		//_dlog(line)
		key := getKey(line)
		if len(key) == 0 {
			// This means ELAPSED_KEY_REGEXP is given but this line doesn't match so OK to skip
			continue
		}
		_dlog(strconv.Itoa(FOUND_COUNT) + " key = " + key)
		// Need to check the end line first before checking the start line.
		if echoEndLine(line, key) {
			continue
		}
		if echoStartLine(line, key) {
			continue
		}

		// not found the start line yet
		if len(FILE_NAME_PFXS[key]) == 0 {
			//_dlog("No START_LINE_PFX for " + key)
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
		f, _ := OUT_FILES[key]
		echoLine(line, f)
	}

	if len(DURATIONS) > 0 {
		echoDurations(DURATIONS)
	}
	if len(START_DATETIMES) > 0 {
		for k, v := range START_DATETIMES {
			pad := len(v)
			fmt.Printf("# %s|%-"+strconv.Itoa(pad)+"s|%8sms|%s\n", v, "<none>", " ", k)
		}
	}
}

func echoStartLine(line string, key string) bool {
	// if no START_REGEXP, immediately stop
	if START_REGEXP == nil {
		return false
	}
	// If the start line of this key is already found, no need to check
	if len(FILE_NAME_PFXS[key]) > 0 {
		return false
	}
	matches := START_REGEXP.FindStringSubmatch(line)
	if len(matches) == 0 {
		return false
	}
	FOUND_COUNT++

	FILE_NAME_PFXS[key] = ""
	if key != NO_KEY {
		FILE_NAME_PFXS[key] = REM_CHAR_REGEXP.ReplaceAllString(key, "") + "_"
	}
	// echo "${_prev_str}" | sed "s/[ =]/_/g" | tr -cd '[:alnum:]._-\n' | cut -c1-192
	FILE_NAME_PFXS[key] += REM_CHAR_REGEXP.ReplaceAllString(matches[len(matches)-1], "_")
	FILE_NAME_PFXS[key] = REM_DUPE_REGEXP.ReplaceAllString(FILE_NAME_PFXS[key], "_")
	//FILE_NAME_PFXS[key] = strings.TrimSuffix(FILE_NAME_PFXS[key], "_")	// To avoid filename_.out
	if len(FILE_NAME_PFXS[key]) > 192 {
		_dlog("Trimming " + FILE_NAME_PFXS[key]) // truncating
		FILE_NAME_PFXS[key] = FILE_NAME_PFXS[key][:192]
	}
	_dlog("START_LINE_PFX: " + FILE_NAME_PFXS[key])

	var f *os.File
	if SPLIT_FILE {
		var err error
		// Not expecting more than 99 threads in one file
		outFilePath := filepath.Join(OUT_DIR, fmt.Sprintf("%02d", FOUND_COUNT)+"_"+FILE_NAME_PFXS[key]+".out")
		// If file exist, stop
		if _, err = os.Stat(outFilePath); err == nil {
			log.Fatal(outFilePath + " already exists.")
		}
		// If previous file is still open, close it
		_, ok := OUT_FILES[key]
		if ok && OUT_FILES[key] != nil {
			_ = OUT_FILES[key].Close()
		}
		OUT_FILES[key], err = os.OpenFile(outFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		helpers.PanicIfErr(err)
		f = OUT_FILES[key]
	}
	setStartDatetimeFromLine(line)
	return echoLine(line, f)
}

func echoEndLine(line string, key string) bool {
	// If no END_REGEXP is set, immediately return
	if END_REGEXP == nil {
		return false
	}
	_, ok := FILE_NAME_PFXS[key]
	if !ok || len(FILE_NAME_PFXS[key]) == 0 {
		return false
	}
	matches := END_REGEXP.FindStringSubmatch(line)
	if len(matches) == 0 {
		return false
	}
	FILE_NAME_PFXS[key] = ""
	isEchoed := false
	f, ok := OUT_FILES[key]
	if len(matches) > 1 {
		// If regex catcher group is used, including that matching characters into current output.
		isEchoed = echoLine(strings.Join(matches[1:], ""), f)
	}
	// If asked to split into multiple files, closing current out file.
	if ok && OUT_FILES[key] != nil {
		_ = OUT_FILES[key].Close()
		OUT_FILES[key] = nil
	}
	// Duration needs to be processed after outputting the end line.
	calcDuration(line)
	return isEchoed
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
	_dlog("No ELAPSED_KEY_REGEX in " + line)
	return ""
}

func setStartDatetimeFromLine(line string) {
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

func calcDuration(endLine string) {
	if ELAPSED_REGEXP == nil {
		_dlog("No ELAPSED_REGEX")
		return
	}
	elapsedEndMatches := ELAPSED_REGEXP.FindStringSubmatch(endLine)
	if len(elapsedEndMatches) == 0 {
		_dlog("No end time match with '" + ELAPSED_REGEX + "' for " + endLine)
		return
	}
	_dlog("elapsedEndMatches = " + elapsedEndMatches[0])
	endTimeStr := elapsedEndMatches[len(elapsedEndMatches)-1]
	_dlog("endTimeStr = " + endTimeStr)
	key := getKey(endLine)
	if len(key) == 0 {
		// If ELAPSED_KEY_REGEX is provided, ELAPSED_REGEXP and ELAPSED_KEY_REGEXP both need to match
		_dlog("ELAPSED_REGEXP matched but not ELAPSED_KEY_REGEXP from " + endLine)
		return
	}
	startTimeStr, ok := START_DATETIMES[key]
	if ok {
		_dlog("startTimeStr = " + startTimeStr)
		duration := calcDurationFromStrings(startTimeStr, endTimeStr)
		dura := Duration{
			startTimeStr: startTimeStr,
			endTimeStr:   endTimeStr,
			durationMs:   duration.Milliseconds(),
			key:          key,
		}
		DURATIONS = append(DURATIONS, dura)
		delete(START_DATETIMES, key)
	} else {
		_, _ = fmt.Fprintf(os.Stderr, "[WARN] No start datetime found for key:%s end datetime:%s.\n", key, endTimeStr)
	}
}

func echoDurations(duras []Duration) {
	maxKeyLen := 0
	minDuraMs := int64(0)
	for _, dura := range duras {
		if maxKeyLen == 0 || len(dura.key) > maxKeyLen {
			maxKeyLen = len(dura.key)
		}
		if minDuraMs == 0 || dura.durationMs < minDuraMs {
			minDuraMs = dura.durationMs
		}
	}
	_dlog("maxKeyLen = " + strconv.Itoa(maxKeyLen))
	_dlog("minDuraMs = " + strconv.FormatInt(minDuraMs, 10))
	firstStartTimeStr := duras[0].startTimeStr
	lastEndTimeStr := duras[len(duras)-1].endTimeStr
	if ASCII_ROTATE_NUM > 0 && ASCII_ROTATE_NUM < len(duras) {
		lastEndTimeStr = duras[ASCII_ROTATE_NUM-1].endTimeStr
	}
	totalDuration := calcDurationFromStrings(firstStartTimeStr, lastEndTimeStr)
	divideMs := totalDuration.Milliseconds() / ASCII_WIDTH
	_dlog("totalDuration / ASCII_WIDTH = " + strconv.FormatInt(divideMs, 10))
	if divideMs > minDuraMs {
		divideMs = minDuraMs
	}
	for i, dura := range duras {
		if ASCII_ROTATE_NUM > 0 && math.Mod(float64(i), float64(ASCII_ROTATE_NUM)) == 0 {
			var t time.Time
			FIRST_START_TIME = t
			_dlog(FIRST_START_TIME.IsZero())
			if ASCII_DISABLED == false {
				fmt.Println("# ")
			}
		}
		echoDurationInner(dura, maxKeyLen, divideMs)
	}
}

func echoDurationInner(dura Duration, maxKeyLen int, divideMs int64) {
	if KEY_PADDING == 0 {
		// min 11, max 32 for now
		KEY_PADDING = 0 - maxKeyLen
		if KEY_PADDING > -11 {
			KEY_PADDING = -11
		} else if KEY_PADDING < -32 {
			KEY_PADDING = -32
		}
		_dlog("KEY_PADDING = " + strconv.Itoa(KEY_PADDING))
	}
	if DIVIDE_MS > 0 {
		// if DIVIDE_MS is specified, using
		divideMs = DIVIDE_MS
	}
	_dlog("divideMs = " + strconv.FormatInt(divideMs, 10))

	ascii := ""
	if ASCII_DISABLED == false {
		ascii = asciiChart(dura.startTimeStr, dura.durationMs, divideMs)
		ascii = "|" + ascii
	}
	if dura.key == NO_KEY {
		// As "sec,ms" contains comma, using "|". Also "<num> ms" for easier sorting (it was "ms:<num>")
		fmt.Printf("# %s|%s|%8dms%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, ascii)
	} else {
		fmt.Printf("# %s|%s|%8dms|%*s%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, KEY_PADDING, dura.key, ascii)
	}
}

func asciiChart(startTimeStr string, durationMs int64, divideMs int64) string {
	var duraSinceFirstSTart time.Duration
	startTime, _ := time.Parse(ELAPSED_FORMAT, startTimeStr)
	if FIRST_START_TIME.IsZero() {
		duraSinceFirstSTart = 0
		FIRST_START_TIME = startTime
		_dlog(startTime)
	} else {
		duraSinceFirstSTart = startTime.Sub(FIRST_START_TIME)
	}
	var ascii = ""
	repeat := int(math.Ceil(float64(duraSinceFirstSTart.Milliseconds()) / float64(divideMs)))
	for i := 0; i < repeat; i++ {
		ascii += " "
	}
	_dlog(repeat)
	repeat = int(math.Ceil(float64(durationMs) / float64(divideMs)))
	for i := 0; i < repeat; i++ {
		ascii += "-"
	}
	_dlog(repeat)
	return ascii
}

func str2time(timeStr string) time.Time {
	if len(ELAPSED_FORMAT) == 0 {
		if len(timeStr) > 12 {
			ELAPSED_FORMAT = "2006-01-02 15:04:05,000"
		} else {
			ELAPSED_FORMAT = "15:04:05,000"
		}
	}
	t, err := time.Parse(ELAPSED_FORMAT, timeStr)
	if err != nil {
		fmt.Println(err) //time.Time{}
	}
	return t
}

func calcDurationFromStrings(startTimeStr string, endTimeStr string) time.Duration {
	startTime := str2time(startTimeStr)
	if startTime.IsZero() {
		return -1
	}
	endTime := time.Now()
	if len(endTimeStr) > 0 {
		endTime = str2time(endTimeStr)
		if endTime.IsZero() {
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
	helpers.DEBUG = _DEBUG
	helpers.Log("DEBUG", message)
}

func closeAllFiles() {
	// Just in case (should be already closed)
	for _, f := range OUT_FILES {
		if f != nil {
			_ = f.Close()
			f = nil
		}
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
	} else if len(os.Args) <= 3 || len(os.Args[3]) == 0 {
		END_REGEXP = START_REGEXP
	}
	if len(os.Args) > 4 && len(os.Args[4]) > 0 {
		OUT_DIR = os.Args[4]
		SPLIT_FILE = true
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

	defer closeAllFiles()
	if IN_FILES == nil || len(IN_FILES) == 0 {
		processFile(os.Stdin)
	} else {
		for _, path := range IN_FILES {
			inFile, err := os.Open(path)
			helpers.PanicIfErr(err)
			//defer inFile.Close()
			processFile(inFile)
			if inFile != nil {
				_ = inFile.Close()
			}
		}
	}
}
