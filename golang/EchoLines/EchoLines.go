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
    echolines [some_file1,some_file2] START_REGEXP [END_REGEXP] [_OUT_DIR]

# NOTE:
    If END_REGEXP is provided but *without any capture group*, the end line is not echoed (not included).
    If the first argument is empty, the script accepts the STDIN.

# ENV VARIABLES:
    SPLIT_FILE=Y
        Save the result into multiple files (if _OUT_DIR is given, this becomes Y automatically)
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
        Used against starting and ending lines *both*. If the log is for multithreading application, provide regex to capture thread Id (eg: "\[([^\]]+)")
    ELAPSED_DIVIDE_MS=<integer milliseconds>
        To deside the width of ascii chart
    ELAPSED_MIN_MS=<integer milliseconds>
        Lower than this duration won't be shown in the ascii chart
    ASCII_DISABLED=Y
        To disable ascii chart (for slightly faster processing)
    ASCII_ROTATE_NUM=<num>
        (experimental) To make ASCII chart width shorter by rotating per <num> lines
	SINGLE_THREAD=Y
        (experimental) If single thread, using the start line key matched by ELAPSED_KEY_REGEX as the label.

# USAGE EXAMPLES:
## Misc. Read the result with 'q' (after "rg '^# (.+)' -o -r '$1' > ./durations.out"):
    q -O -d"|" -T "SELECT c1 as start_time, c2 as end_time, CAST(c3 as INT) as ms, c4 as key FROM ./durations.out WHERE ms > 10000 ORDER BY ms DESC"
    q -O -d"|" -T "SELECT AVG(CAST(c3 as INT)) as avg_ms, MIN(CAST(c3 as INT)) as min_ms, MAX(CAST(c3 as INT)) as max_ms, count(*) as c FROM ./durations.out"

## Thread dumps
### NXRM2 thread dumps (not perfect. still contains some junk lines):
    EXCL_REGEX="^(jvm 1\s+\|\s+\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d.+|.+Pause reading child output to share cycles.+)" echolines "wrapper.log.2,wrapper.log.1,wrapper.log" "^jvm 1\s+\|\s+\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+)" | sed 's/^jvm 1    | //' > threads.txt
### NXRM3 thread dumps:
    HTML_REMOVE=Y echolines "./jvm.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+|^\s+Metaspace\s+.+)" > threads.txt
#### If would like to split the thread dumps per datetime. Considering in case the datetime includes the timezone (eg. +09:00)
    echolines ./threads.txt '^20\d\d-\d\d-\d\d.\d\d:\d\d:\d\d\S{0,6}$' '' "threads_per_datetime"
    #echolines "threads.txt" "^\".+" "" "./threads_per_thread"
    find ./threads_per_dump -type f -name '[0-9]*_*.out' | xargs -P3 -t -I{} bash -c '_d="$(basename "{}" ".out")";echolines "{}" "^\".+" "" "./threads_per_thread/${_d}"'
### IQ thread dumps from the STDOUT file (not perfect. may contains some junk lines):
    HTML_REMOVE=Y EXCL_REGEX="^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d.\d\d\d\d" echolines "./iq-server.out" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+class space.+|^\s+Metaspace\s+.+)" > threads.txt

## Durations
NOTE: "rg" is used several times in the below examples because it is faster than this tool for filtering the results.

### For each line per thread #with thread+username+classnames:
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y #ELAPSED_KEY_REGEX="(\[qtp\S+\s\S*\s\S+)"
    rg 'qtp1529377038-106' ./nexus.log | echolines "" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" | rg '^# ' | sort -t'|' -k3n
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y ELAPSED_KEY_REGEX="\[FelixStartLevel\]\s+\S+\s+(\S+)" ELAPSED_MIN_MS=100
	rg '\[FelixStartLevel\]' ./log/nexus.log | echolines "" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" | rg '^# ' | sort -n
    # For the above example, including "jetty-main-1" may be useful but could be too noisy 
### (Not so useful but) similar to the above but excluding empty username:
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y ELAPSED_KEY_REGEX="(\[dw\-[^\]]+\]\s\S+\s\S+)"
    echolines "_hourly_logs/clm-server_2024-09-13_16.out" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d" | rg '^# ' | sort -t'|' -k3n
### NXRM3: SQL queries #and sort by the longest:
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y ELAPSED_KEY_REGEX="(\[[^\]]+\])"
    echolines "./log/nexus.log" " - ==>  Preparing:" "(^.+ - <== .+)" | rg '^# (.+)' -o -r '$1'    #| sort -t'|' -k3n
### NXRM3: Specific method, which stops if 0 update, and related log lines:
    echolines "./log/nexus.log" "trimBrowseNodes - ==>  Preparing:" "(^.+Updates: 0)" | tee trimBrowseNodes.log | rg '^# (.+)' -o -r '$1' > trimBrowseNodes_dur.out
### NXRM3: (estimated) durations by checking org.apache.http = DEBUG, http-outgoing-\d+
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y
    #rg '2025-08-27 16:.+qtp173256813-1890.+DefaultManagedHttpClientConnection - http-outgoing-\d+: (set socket timeout|Close connection)' ./log/nexus.log
    rg '2025-08-27 16:.+qtp173256813-1890.+.(MainClientExec - Executing request|DefaultManagedHttpClientConnection - http-outgoing-\d+: Close connection)' ./log/nexus.log > qtp173256813-1890_executing_request.out
	echolines ./qtp173256813-1890_executing_request.out "MainClientExec - Executing request (.+)" "^.+Close connection.*" | rg '^# ' | sort -t'|' -k3n

### NXRM3: the first 30 S3 pool requests (with org.apache.http = DEBUG. This example also checks 'Connection leased'):
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[(s3-parallel-[^\]]+)"
    rg -m30 '\[s3-parallel-.+ Connection (request|leased|released):' ./log/nexus.log > connections.out
    sed -n "1,30p" connections.out | echolines "" " leased:" "(^.+ released:.+)" | rg '^# '
### NXRM3: Tasks
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="Task '([^']+)'" ASCII_DISABLED=Y
    echolines "./log/nexus.log" "QuartzTaskInfo .+ -> RUNNING" "(^.+QuartzTaskInfo .+ RUNNING -> .+)" | rg '^# (.+)' -o -r '$1' | sort -t'|' -k2
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[([^\]]+)" ASCII_DISABLED=Y
    echolines "./log/tasks/allTasks.log" " - Task information:" "(^.+ - Task complete)" "per_thread" | rg '^# (.+)' -o -r '$1' | sort -t'|' -k2
### NXRM3: blob-store-group-removal-\d+ .bytes files, with ASCII
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="(blob-store-group-removal-\d+)"
    rg 'blob-store-group-removal-\d+' -m2000 nexus.log | echolines "" "Writing blob" "(^.+Finished upload to key.+)" | rg '^# (.+)' -o -r '$1' > bytes_duration_summary.tsv
### NXRM3: DEBUG cooperation2.datastore.internal.CooperatingFuture
    export ELAPSED_REGEX="\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[(qtp[^\]]+)"
    rg -F '/dotenv?null' -m2000 nexus.log | echolines "" "Requesting" "(^.+Completing.+)" | rg '^# (.+)' -o -r '$1' > bytes_duration_summary.tsv
### NXRM3: Yum group merging duration
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y ELAPSED_KEY_REGEX="(\[qtp\S+\s\S*\s\S+)"
    rg YumGroupMergerImpl ./nexus3.log | echolines "" ".+ starting$" "(^.+ completed)$" | rg '^#'
### NXRM3: Duration by BlobID for single thread task log
	export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ASCII_DISABLED=Y
	export ELAPSED_KEY_REGEX="[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}" SINGLE_THREAD=Y
	rg 'Next available record for compaction' ./blobstore.compact-20250711145938010.log | echolines ""	# to use STDIN

### IQ: Evaluating a File, and sort by threadId and time
    rg 'POST /rest/scan/.+Scheduling scan task (\S+)' -o -r '$1' log/clm-server.log | xargs -I{} rg -w "{}" ./log/clm-server.log | sort | uniq > scan_tasks.log
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[([^ \]]+)"
    echolines ./scan_tasks.log "Running scan task" "(^.+Completed scan task.+)" | rg '^# (.+)' -o -r '$1' | sort -t'|' -k3,3 -k1,1
### IQ: Evaluation for Firewall
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="\[(dw\-\d+ \- POST /rest/integration/artifactory/repositories[^ \]]+)" ASCII_DISABLED="Y"
    echolines ./clm-server_mini.out "Evaluating components for repository" "(^.+ Evaluated .+)" | rg '^# (.+)' -o -r '$1' | sort -t'|' -k3,3 -k1,1

### Get duration of Eclipse Memory Analyzer Tool (MAT) threads (<file-name>.threads)
    echolines ./java_pid1404494.threads "^Thread 0x\S+" "" "./threads_per_thread"

### Get duration postgresql.log for Nexus 3 startup (so single thread)
    export ELAPSED_REGEX="^\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d)" ASCII_DISABLED=Y
    echolines ./execute_sqls.out "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d" "^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d" | rg '^# '

### Get duration of mvn/maven download (need org.slf4j.simpleLogger.showDateTime=true org.slf4j.simpleLogger.dateTimeFormat=yyyy-MM-dd HH:mm:ss.SSS)
    export ELAPSED_REGEX="^\[?\d\d\d\d-\d\d-\d\d.(\d\d:\d\d:\d\d.\d\d\d)" ELAPSED_KEY_REGEX="https?://\S+" EXTRA_FROM_ENDLINE_REGEX="\([0-9.]+ \S+ at [0-9.]+ \S+/s\)$" ASCII_DISABLED=Y
    echolines ./mvn.log "Downloading from \S+: \S+" "(^.+Downloaded from \S+: \S+)" | rg '^# ' > durations.out
    # After adding headers
    q -O -d"|" -H -T "SELECT * FROM ./durations.out WHERE MISC NOT LIKE '% MB/s)' ORDER BY MS DESC LIMIT 10"
END`)
}

var _DEBUG = helpers.GetBoolEnv("_DEBUG", false)
var DEFAULT_START_REGEX = `^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d\d\d`
var START_REGEXP *regexp.Regexp
var END_REGEXP *regexp.Regexp
var INCL_REGEX = os.Getenv("INCL_REGEX")
var INCL_REGEXP *regexp.Regexp
var EXCL_REGEX = os.Getenv("EXCL_REGEX")
var EXCL_REGEXP *regexp.Regexp
var ELAPSED_REGEX = os.Getenv("ELAPSED_REGEX") // Usually datetime regex
var ELAPSED_REGEXP *regexp.Regexp
var ELAPSED_KEY_REGEX = os.Getenv("ELAPSED_KEY_REGEX") // Used to capture the key from the *end line*
var ELAPSED_KEY_REGEXP *regexp.Regexp
var EXTRA_FROM_ENDLINE_REGEX = os.Getenv("EXTRA_FROM_ENDLINE_REGEX") // Used to capture the key from the *end line*
var EXTRA_FROM_ENDLINE_REGEXP *regexp.Regexp
var ELAPSED_FORMAT = os.Getenv("ELAPSED_FORMAT") // If datetime format is different from the default
var ASCII_WIDTH = helpers.GetEnvInt64("ASCII_WIDTH", 100)
var ASCII_ROTATE_NUM = helpers.GetEnvInt("ASCII_ROTATE_NUM", -1)

var HTML_REMOVE = helpers.GetBoolEnv("HTML_REMOVE", false)
var ASCII_DISABLED = helpers.GetBoolEnv("ASCII_DISABLED", false)
var SPLIT_FILE = helpers.GetBoolEnv("SPLIT_FILE", false)
var ELAPSED_DIVIDE_MS = helpers.GetEnvInt64("ELAPSED_DIVIDE_MS", -1)
var ELAPSED_MIN_MS = helpers.GetEnvInt64("ELAPSED_MIN_MS", -1)
var SINGLE_THREAD = helpers.GetBoolEnv("SINGLE_THREAD", false)

var REM_CHAR_REGEXP = regexp.MustCompile(`[^0-9a-zA-Z_]`)
var REM_DUPE_REGEXP = regexp.MustCompile(`[_]+`)
var TAG_REGEXP = regexp.MustCompile(`<[^>]+>`)

var _NO_KEY = "no-key" // When no ELAPSED_KEY_REGEX, and indicating single thread
var _LAST_KEY = ""     // Used with SINGLE_THREAD to remember the last key
var _IN_FILES []string
var _OUT_DIR = ""
var _OUT_FILES = make(map[string]*os.File)
var _START_DATETIMES = make(map[string]string)
var _FILE_NAME_PFXS = make(map[string]string)
var _FIRST_START_TIME time.Time
var _KEY_PADDING = 0
var _FOUND_COUNT = 0

// fmt.Printf("# s:%s | e:%s | %8d | %*s | %s\n", startTimeStr, endTimeStr, duration.Milliseconds(), _KEY_PADDING, key, ascii)
type Duration struct {
	startTimeStr string
	endTimeStr   string
	durationMs   int64
	key          string
	label        string
}

var _DURATIONS = make([]Duration, 0)

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
		//helpers.Log("DEBUG", line)
		key := getKey(line)
		if len(key) == 0 {
			// This means ELAPSED_KEY_REGEXP is given but this line doesn't match so OK to skip
			//helpers.Log("DEBUG", "Skipping because no key from getKey")
			continue
		}
		if key != _NO_KEY {
			helpers.Log("DEBUG", "getKey returned key:"+key)
		}
		// Need to check the end line first before checking the start line.
		if echoEndLine(line, key) {
			continue
		}
		if echoStartLine(line, key) {
			continue
		}

		// not found the start line yet
		if len(_FILE_NAME_PFXS[key]) == 0 {
			//helpers.Log("DEBUG", "No _FILE_NAME_PFXS[key] for " + key)
			continue
		}
		if INCL_REGEXP != nil && !INCL_REGEXP.MatchString(line) {
			helpers.Log("DEBUG", "Did not match with INCL_REGEX:"+INCL_REGEX)
			continue
		}
		if EXCL_REGEXP != nil && EXCL_REGEXP.MatchString(line) {
			helpers.Log("DEBUG", "Matched with EXCL_REGEX:"+EXCL_REGEX)
			continue
		}
		f, _ := _OUT_FILES[key]
		echoLine(line, f)
	}

	if len(_DURATIONS) > 0 {
		echoDurations(_DURATIONS)
	}
	// Outputting lines which didn't have the duration (no matching start/end time)
	if len(_START_DATETIMES) > 0 {
		for k, v := range _START_DATETIMES {
			pad := len(v)
			fmt.Printf("# %s|%-"+strconv.Itoa(pad)+"s|%8s|%s\n", v, "<none>", " ", k)
		}
	}
}

func echoStartLine(line string, key string) bool {
	// if no START_REGEXP, immediately stop
	if START_REGEXP == nil {
		return false
	}
	// If the start line of this key is already found, no need to check
	if len(_FILE_NAME_PFXS[key]) > 0 {
		return false
	}
	matches := START_REGEXP.FindStringSubmatch(line)
	if len(matches) == 0 {
		return false
	}
	// All validations passed, so incrementing _FOUND_COUNT
	_FOUND_COUNT++
	setStartDatetimeFromLine(line)

	_FILE_NAME_PFXS[key] = ""
	if key != _NO_KEY {
		helpers.Log("DEBUG", "As not 'no key' cleaning up the "+_FILE_NAME_PFXS[key])
		_FILE_NAME_PFXS[key] = REM_CHAR_REGEXP.ReplaceAllString(key, "") + "_"
	}
	// echo "${_prev_str}" | sed "s/[ =]/_/g" | tr -cd '[:alnum:]._-\n' | cut -c1-192
	_FILE_NAME_PFXS[key] += REM_CHAR_REGEXP.ReplaceAllString(matches[len(matches)-1], "_")
	_FILE_NAME_PFXS[key] = REM_DUPE_REGEXP.ReplaceAllString(_FILE_NAME_PFXS[key], "_")
	//_FILE_NAME_PFXS[key] = strings.TrimSuffix(_FILE_NAME_PFXS[key], "_")    // To avoid filename_.out
	if len(_FILE_NAME_PFXS[key]) > 192 {
		helpers.Log("DEBUG", "Trimming "+_FILE_NAME_PFXS[key]) // truncating
		_FILE_NAME_PFXS[key] = _FILE_NAME_PFXS[key][:192]
	}
	helpers.Log("DEBUG", "_FILE_NAME_PFXS[key]: "+_FILE_NAME_PFXS[key]+" for "+key)

	var f *os.File
	if SPLIT_FILE {
		var err error
		// Not expecting more than 99 threads in one file
		outFilePath := filepath.Join(_OUT_DIR, fmt.Sprintf("%02d", _FOUND_COUNT)+"_"+_FILE_NAME_PFXS[key]+".out")
		// If file exist, stop
		if _, err = os.Stat(outFilePath); err == nil {
			log.Fatal(outFilePath + " already exists.")
		}
		// If previous file *exists*, close it
		_, ok := _OUT_FILES[key]
		if ok && _OUT_FILES[key] != nil {
			_ = _OUT_FILES[key].Close()
		}
		// Open the file for writing
		_OUT_FILES[key], err = os.OpenFile(outFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		helpers.PanicIfErr(err)
		f = _OUT_FILES[key]
	}

	return echoLine(line, f)
}

func echoEndLine(line string, key string) bool {
	// If no END_REGEXP is set, immediately return
	if END_REGEXP == nil {
		helpers.Log("DEBUG", "No END_REGEXP (no calcDuration)")
		return false
	}

	// Can't remember why checking _FILE_NAME_PFXS is needed, but commenting as it returns in here.
	//_, ok := _FILE_NAME_PFXS[key]
	//if !ok || len(_FILE_NAME_PFXS[key]) == 0 {
	//	helpers.Log("DEBUG", "No _FILE_NAME_PFXS[key] for "+key+" (no calcDuration)")
	//	return false
	//}
	if len(_START_DATETIMES) == 0 {
		//helpers.Log("DEBUG", "_START_DATETIMES is empty so skipping")
		return false
	}

	matches := END_REGEXP.FindStringSubmatch(line)
	if len(matches) == 0 {
		helpers.Log("DEBUG", "No match with END_REGEXP (no calcDuration)")
		return false
	}
	// May need to reset the value only when END_REGEXP matches
	_FILE_NAME_PFXS[key] = ""
	isEchoed := false
	f, ok := _OUT_FILES[key]
	if ok && len(matches) > 1 {
		// If regex catcher group is used, including that matching characters into current output.
		isEchoed = echoLine(strings.Join(matches[1:], ""), f)
	}
	// If asked to split into multiple files, closing current out file.
	if ok && _OUT_FILES[key] != nil {
		_ = _OUT_FILES[key].Close()
		_OUT_FILES[key] = nil
	}
	// Duration needs to be processed after outputting the end line.
	calcDuration(line)
	return isEchoed
}

func getKey(line string) string {
	if ELAPSED_KEY_REGEXP == nil {
		// no regex specified, return the default value
		return _NO_KEY
	}

	elapsedKeyMatches := ELAPSED_KEY_REGEXP.FindStringSubmatch(line)
	if len(elapsedKeyMatches) > 0 {
		helpers.Log("DEBUG", "elapsedKeyMatches[0] = "+elapsedKeyMatches[0])
		return elapsedKeyMatches[len(elapsedKeyMatches)-1]
	}
	// if the line doesn't have key, just empty string
	//helpers.Log("DEBUG", "No elapsedKeyMatches in "+line)
	return ""
}

func setStartDatetimeFromLine(line string) {
	if ELAPSED_REGEXP == nil {
		helpers.Log("DEBUG", "No ELAPSED_REGEX")
		return
	}
	elapsedStartMatches := ELAPSED_REGEXP.FindStringSubmatch(line)
	if len(elapsedStartMatches) == 0 {
		helpers.Log("DEBUG", "No match with '"+ELAPSED_REGEX)
		return
	}
	helpers.Log("DEBUG", elapsedStartMatches)
	elapsedStart := elapsedStartMatches[len(elapsedStartMatches)-1]
	key := getKey(line)
	if len(key) == 0 {
		helpers.Log("DEBUG", "ELAPSED_REGEXP matched but not ELAPSED_KEY_REGEXP (no _START_DATETIMES)")
		return
	}
	_key := key
	if SINGLE_THREAD {
		_LAST_KEY = key
		_key = _NO_KEY
	}
	helpers.Log("DEBUG", "Adding _START_DATETIMES["+key+"] ("+_key+") = "+elapsedStart)
	// TODO: should care if it's already set?
	_START_DATETIMES[_key] = elapsedStart
}

func calcDuration(endLine string) {
	// Calculate the duration from the *end* line (also checks started time)
	if ELAPSED_REGEXP == nil {
		helpers.Log("DEBUG", "No ELAPSED_REGEX")
		return
	}

	endkey := getKey(endLine)
	if len(endkey) == 0 {
		// If ELAPSED_KEY_REGEX is provided, ELAPSED_REGEXP and ELAPSED_KEY_REGEXP both need to match
		helpers.Log("DEBUG", "ELAPSED_REGEXP matched but not ELAPSED_KEY_REGEXP (or no _NO_KEY) for "+endLine)
		return
	}

	elapsedEndMatches := ELAPSED_REGEXP.FindStringSubmatch(endLine)
	if len(elapsedEndMatches) == 0 {
		helpers.Log("DEBUG", "Skipping as no end time match with '"+ELAPSED_REGEX+"' for "+endkey)
		return
	}
	//helpers.Log("DEBUG", "elapsedEndMatches = "+elapsedEndMatches[0])
	endTimeStr := elapsedEndMatches[len(elapsedEndMatches)-1]
	helpers.Log("DEBUG", "endTimeStr = "+endTimeStr+" for "+endkey)
	_key := endkey
	if SINGLE_THREAD {
		_key = _NO_KEY
	}
	startTimeStr, ok := _START_DATETIMES[_key]
	if !ok {
		helpers.Log("WARN", "No start datetime found for endkey:"+endkey+" ("+_key+") end datetime:"+endTimeStr)
		return
	}
	helpers.Log("DEBUG", "startTimeStr = "+startTimeStr+" for "+endkey)
	duration := calcDurationFromStrings(startTimeStr, endTimeStr)

	label := _LAST_KEY
	if EXTRA_FROM_ENDLINE_REGEXP != nil {
		labelMatches := EXTRA_FROM_ENDLINE_REGEXP.FindStringSubmatch(endLine)
		if len(labelMatches) > 0 {
			// If regex catcher group is used, including that matching characters into current output.
			helpers.Log("DEBUG", "labelMatches = "+labelMatches[0])
			label = labelMatches[len(labelMatches)-1]
		}
	}
	dura := Duration{
		startTimeStr: startTimeStr,
		endTimeStr:   endTimeStr,
		durationMs:   duration.Milliseconds(),
		key:          _key,
		label:        label,
	}
	_DURATIONS = append(_DURATIONS, dura)
	helpers.Log("DEBUG", dura)
	delete(_START_DATETIMES, _key)
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
	helpers.Log("DEBUG", "maxKeyLen = "+strconv.Itoa(maxKeyLen))
	helpers.Log("DEBUG", "minDuraMs = "+strconv.FormatInt(minDuraMs, 10))
	firstStartTimeStr := duras[0].startTimeStr
	lastEndTimeStr := duras[len(duras)-1].endTimeStr
	if ASCII_ROTATE_NUM > 0 && ASCII_ROTATE_NUM < len(duras) {
		lastEndTimeStr = duras[ASCII_ROTATE_NUM-1].endTimeStr
	}
	totalDuration := calcDurationFromStrings(firstStartTimeStr, lastEndTimeStr)
	divideMs := totalDuration.Milliseconds() / ASCII_WIDTH
	helpers.Log("DEBUG", "totalDuration / ASCII_WIDTH = "+strconv.FormatInt(divideMs, 10))
	if minDuraMs > 0 && divideMs > minDuraMs {
		divideMs = minDuraMs
	}
	for i, dura := range duras {
		if ASCII_ROTATE_NUM > 0 && math.Mod(float64(i), float64(ASCII_ROTATE_NUM)) == 0 {
			var t time.Time
			_FIRST_START_TIME = t
			helpers.Log("DEBUG", _FIRST_START_TIME.IsZero())
			if ASCII_DISABLED == false {
				fmt.Println("# ")
			}
		}
		echoDurationInner(dura, maxKeyLen, divideMs)
	}
}

func echoDurationInner(dura Duration, maxKeyLen int, divideMs int64) {
	// Even if dura.durationMs == 0, still output. Only if ELAPSED_MIN_MS is set, skip.
	if ELAPSED_MIN_MS > 0 && dura.durationMs < ELAPSED_MIN_MS {
		return
	}
	if _KEY_PADDING == 0 {
		// min 11, max 32 for now
		_KEY_PADDING = 0 - maxKeyLen
		if _KEY_PADDING > -11 {
			_KEY_PADDING = -11
		} else if _KEY_PADDING < -32 {
			_KEY_PADDING = -32
		}
		helpers.Log("DEBUG", "_KEY_PADDING = "+strconv.Itoa(_KEY_PADDING))
	}
	if ELAPSED_DIVIDE_MS > 0 {
		// if ELAPSED_DIVIDE_MS is specified, override the value
		divideMs = ELAPSED_DIVIDE_MS
	}

	ascii := ""
	if ASCII_DISABLED == false {
		helpers.Log("DEBUG", "divideMs = "+strconv.FormatInt(divideMs, 10))
		helpers.Log("DEBUG", "durationMs = "+strconv.FormatInt(dura.durationMs, 10))
		ascii = asciiChart(dura.startTimeStr, dura.durationMs, divideMs)
		ascii = "|" + ascii
	}
	if SINGLE_THREAD && len(dura.label) > 0 {
		fmt.Printf("# %s|%s|%8d|%*s%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, _KEY_PADDING, dura.label, ascii)
	} else if dura.key == _NO_KEY {
		fmt.Printf("# %s|%s|%8d%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, ascii)
	} else if len(dura.label) > 0 {
		fmt.Printf("# %s|%s|%8d|%*s%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, _KEY_PADDING, dura.key+" "+dura.label, ascii)
	} else {
		fmt.Printf("# %s|%s|%8d|%*s%s\n", dura.startTimeStr, dura.endTimeStr, dura.durationMs, _KEY_PADDING, dura.key, ascii)
	}
}

func asciiChart(startTimeStr string, durationMs int64, divideMs int64) string {
	var duraSinceFirstSTart time.Duration
	startTime, _ := time.Parse(ELAPSED_FORMAT, startTimeStr)
	if _FIRST_START_TIME.IsZero() {
		duraSinceFirstSTart = 0
		_FIRST_START_TIME = startTime
		helpers.Log("DEBUG", startTime)
	} else {
		duraSinceFirstSTart = startTime.Sub(_FIRST_START_TIME)
	}
	var ascii = ""
	var repeat = 0
	var repeat2 = 0
	if divideMs > 1 {
		repeat = int(math.Ceil(float64(duraSinceFirstSTart.Milliseconds()) / float64(divideMs)))
		repeat2 = int(math.Ceil(float64(durationMs) / float64(divideMs)))
		helpers.Log("DEBUG", "repeat = "+strconv.Itoa(repeat))
		helpers.Log("DEBUG", "repeat2 = "+strconv.Itoa(repeat2))
	}
	for i := 0; i < repeat; i++ {
		ascii += " "
	}
	for i := 0; i < repeat2; i++ {
		ascii += "-"
	}
	return ascii
}

func str2time(timeStr string) time.Time {
	if len(ELAPSED_FORMAT) == 0 {
		if len(timeStr) > 19 {
			ELAPSED_FORMAT = "2006-01-02 15:04:05,000"
		} else if len(timeStr) == 19 {
			ELAPSED_FORMAT = "2006-01-02 15:04:05"
		} else if len(timeStr) == 8 {
			ELAPSED_FORMAT = "15:04:05"
		} else {
			ELAPSED_FORMAT = "15:04:05,000"
		}
	}
	helpers.Log("DEBUG", "ELAPSED_FORMAT:"+ELAPSED_FORMAT+" for "+timeStr)
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

func closeAllFiles() {
	// Just in case (should be already closed)
	for _, f := range _OUT_FILES {
		if f != nil {
			_ = f.Close()
			f = nil
		}
	}
}

func main() {
	helpers.DEBUG = _DEBUG

	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		return
	}

	if len(os.Args) > 1 && len(os.Args[1]) > 0 {
		_IN_FILES = strings.Split(os.Args[1], ",")
	}
	if len(os.Args) > 2 && len(os.Args[2]) > 0 {
		START_REGEXP = regexp.MustCompile(os.Args[2])
	} else {
		helpers.PrintErr("# No START_REGEXP. Compiling " + DEFAULT_START_REGEX)
		START_REGEXP = regexp.MustCompile(DEFAULT_START_REGEX)
		if len(ELAPSED_REGEX) == 0 {
			helpers.PrintErr("# No ELAPSED_REGEX. Using " + DEFAULT_START_REGEX)
			ELAPSED_REGEX = DEFAULT_START_REGEX
		}
	}
	if len(os.Args) > 3 && len(os.Args[3]) > 0 {
		END_REGEXP = regexp.MustCompile(os.Args[3])
	} else if len(os.Args) <= 3 || len(os.Args[3]) == 0 {
		END_REGEXP = START_REGEXP
	}
	if len(os.Args) > 4 && len(os.Args[4]) > 0 {
		_OUT_DIR = os.Args[4]
		SPLIT_FILE = true
		helpers.Log("DEBUG", "4th arg (_OUT_DIR) is provided, so that setting SPLIT_FILE to true")
		_ = os.MkdirAll(_OUT_DIR, os.ModePerm)
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
	if len(EXTRA_FROM_ENDLINE_REGEX) > 0 {
		EXTRA_FROM_ENDLINE_REGEXP = regexp.MustCompile(EXTRA_FROM_ENDLINE_REGEX)
	}

	defer closeAllFiles()
	if _IN_FILES == nil || len(_IN_FILES) == 0 {
		processFile(os.Stdin)
	} else {
		for _, path := range _IN_FILES {
			inFile, err := os.Open(path)
			if err != nil {
				helpers.PrintErr(err)
				continue
			}
			//defer inFile.Close()
			processFile(inFile)
			if inFile != nil {
				_ = inFile.Close()
			}
		}
	}
}
