/*
#go mod init github.com/hajimeo/samples/golang/FileList
#go mod tidy
go build -o ../../misc/file-list_$(uname) FileList.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/file-list_Linux FileList.go
$HOME/IdeaProjects/samples/misc/file-list_$(uname) -b <workingDirectory>/blobs/default/content -p "vol-" -c1 10
*/

package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
)

func usage() {
	// TODO: update usage
	fmt.Println(`
List AWS S3 objects as CSV (Key,LastModified,Size,Owner,Tags).
Usually it takes about 1 second for 1000 objects.

DOWNLOAD and INSTALL:
    curl -o /usr/local/bin/file-list -L https://github.com/hajimeo/samples/raw/master/misc/file-list_$(uname)
    chmod a+x /usr/local/bin/file-list
    
USAGE EXAMPLES:
    file-list -b <workingDirectory>/blobs/default/content -p "vol-" -c1 10

ARGUMENTS:
    -b BaseDir_str  Base directory path (eg: <workingDirectory>/blobs/default/content)
    -p Prefix_str   List only objects which directory *name* starts with this prefix (eg: val-)
    -f Filter_str   List only objects which path contains this string (eg. .properties)
    -fP Filter_str  List .properties file (no .bytes files) which contains this string (much slower)
                    Also, this enables -f ".properties" and -P.
    -n topN_num     Return first/top N results only
    -c concurrency  Executing walk per sub directory in parallel (may not need with very fast disk)
    -P              Get properties (can be very slower)
    -R              Treat -fP value as regex
    -H              No column Header line
    -X              Verbose log output`)
}

// Arguments
var _BASEDIR *string
var _PREFIX *string
var _FILTER *string
var _FILTER2 *string
var _TOP_N *int64
var _CONC_1 *int

//var _CONC_2 *int	// TODO: not implementing this for now
var _WITH_PROPS *bool
var _NO_HEADER *bool
var _USE_REGEX *bool
var _R *regexp.Regexp
var _DEBUG *bool

var _PRINTED_N int64 // Atomic (maybe slower?)
var _TTL_SIZE int64  // Atomic (maybe slower?)

func _log(level string, message string) {
	if level != "DEBUG" || *_DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func printLine(path string, f os.FileInfo) {
	output := fmt.Sprintf("\"%s\",\"%s\",%d", path, f.ModTime(), f.Size())
	// Checking props first because if _FILTER2 is given and match, do not check others.
	props := ""
	if *_WITH_PROPS && strings.HasSuffix(path, ".properties") {
		_log("DEBUG", fmt.Sprintf("Getting properties for %s", path))
		bytes, err := os.ReadFile(path)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving tags for %s failed with %s. Ignoring...", path, err.Error()))
		} else {
			contents := strings.TrimSpace(string(bytes))
			if len(*_FILTER2) == 0 {
				// If no _FILETER2, just return the contents as single line. Should also escape '"'?
				props = strings.ReplaceAll(contents, "\n", ",")
			} else {
				// Otherwise, return properties lines only if contents match.
				if *_USE_REGEX { //len(_R.String()) > 0
					// To allow to use simpler regex, sorting line and converting to single line firt
					lines := strings.Split(strings.TrimSpace(string(bytes)), "\n")
					sort.Strings(lines)
					contents = strings.Join(lines, ",")
					if _R.MatchString(contents) {
						props = contents
					} else {
						_log("DEBUG", fmt.Sprintf("Properties of %s does not contain %s (with Regex). Not outputting entire line...", path, *_FILTER2))
						return
					}
				} else {
					if strings.Contains(contents, *_FILTER2) {
						props = strings.ReplaceAll(contents, "\n", ",")
					} else {
						_log("DEBUG", fmt.Sprintf("Properties of %s does not contain %s (with Regex). Not outputting entire line...", path, *_FILTER2))
						return
					}
				}
			}
		}
	}

	if *_WITH_PROPS {
		output = fmt.Sprintf("%s,\"%s\"", output, props)
	}
	atomic.AddInt64(&_PRINTED_N, 1)
	atomic.AddInt64(&_TTL_SIZE, f.Size())
	fmt.Println(output)
}

// get *all* directories under basedir and which name starts with prefix
func getDirs(basedir string, prefix string) []string {
	dirs := []string{}
	err := filepath.Walk(basedir, func(path string, f os.FileInfo, err error) error {
		if f.IsDir() {
			if len(prefix) == 0 || strings.HasPrefix(f.Name(), prefix) {
				dirs = append(dirs, path)
			}
		}
		return nil
	})
	if err != nil {
		println("Got error retrieving list of directories:")
		panic(err.Error())
	}
	return dirs
}

func listObjects(basedir string) {
	err := filepath.Walk(basedir, func(path string, f os.FileInfo, err error) error {
		if !f.IsDir() {
			if len(*_FILTER) == 0 || strings.Contains(f.Name(), *_FILTER) {
				printLine(path, f)
				if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
					_log("DEBUG", fmt.Sprintf("Printed %d >= %d", _PRINTED_N, *_TOP_N))
					return io.EOF
				}
			}
		}
		return nil
	})
	if err != nil && err != io.EOF {
		println("Got error retrieving list of files:")
		panic(err.Error())
	}
}

// Define, set, and validate command arguments
func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	_BASEDIR = flag.String("b", ".", "Base directory (default: '.')")
	_PREFIX = flag.String("p", "", "The prefix of directory/file name (eg: vol-)")
	_FILTER = flag.String("f", "", "Filter string for file paths (eg: .properties)")
	_FILTER2 = flag.String("fP", "", "Filter string for properties (-P is required)")
	_TOP_N = flag.Int64("n", 0, "Return only first N keys (0 = no limit)")
	_CONC_1 = flag.Int("c", 1, "Concurrent number for sub directories (may not need to use with very fast disk)")
	_WITH_PROPS = flag.Bool("P", false, "If true, also get the contents of .properties files")
	_USE_REGEX = flag.Bool("R", false, "If true, regexp.MatchString is used for _FILTER2")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	flag.Parse()

	if len(*_FILTER2) > 0 {
		*_FILTER = ".properties"
		*_WITH_PROPS = true
		_R, _ = regexp.Compile(*_FILTER2)
	}

	if !*_NO_HEADER && *_WITH_PROPS {
		_log("WARN", "With Properties (-P), listing can be slower.")
	}

	if *_CONC_1 < 1 {
		_log("ERROR", "_CONC_1 is lower than 1.")
		os.Exit(1)
	}

	if !*_NO_HEADER {
		fmt.Print("Path,LastModified,Size")
		if *_WITH_PROPS {
			fmt.Print(",Properties")
		}
		fmt.Println("")
	}

	_log("INFO", fmt.Sprintf("Generating list with %s ...", *_BASEDIR))

	subDirs := make([]string, 1)
	subDirs = append(subDirs, *_BASEDIR)
	if *_CONC_1 > 1 {
		_log("DEBUG", fmt.Sprintf("Retriving sub directories under %s", *_BASEDIR))
		subDirs = getDirs(*_BASEDIR, *_PREFIX)
	}

	wg := sync.WaitGroup{}
	guard := make(chan struct{}, *_CONC_1)
	for _, s := range subDirs {
		if len(s) == 0 {
			//_log("DEBUG", "Ignoring empty sub directory.")
			continue
		}
		_log("DEBUG", "subDir: "+s)
		guard <- struct{}{}
		wg.Add(1) // *
		go func(basedir string) {
			_log("DEBUG", fmt.Sprintf("Listing objects for %s ...", basedir))
			listObjects(basedir)
			<-guard
			wg.Done()
		}(s)
	}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Printed %d items (size: %d) in %s with prefix: '%s'", _PRINTED_N, _TTL_SIZE, *_BASEDIR, *_PREFIX))
}
