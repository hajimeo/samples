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
	"github.com/pkg/errors"
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
List .properties and .bytes files as CSV (Path,LastModified,Size).
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/tree/master/golang/FileList`)
}

// Arguments
var _BASEDIR *string
var _PREFIX *string
var _FILTER *string
var _FILTER2 *string
var _TOP_N *int64
var _CONC_1 *int

//var _CONC_2 *int	// TODO: not implementing this for now
var _LIST_DIRS *bool
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
					lines := strings.Split(contents, "\n")
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
	var dirs []string
	basedir = strings.TrimSuffix(basedir, string(filepath.Separator))
	fp, err := os.Open(basedir)
	if err != nil {
		println("os.Open for " + basedir + " failed.")
		panic(err.Error())
	}
	list, _ := fp.Readdir(0) // 0 to read all files and folders
	for _, f := range list {
		if f.IsDir() {
			if len(prefix) == 0 || strings.HasPrefix(f.Name(), prefix) {
				dirs = append(dirs, basedir+string(filepath.Separator)+f.Name())
			}
		}
	}
	return dirs
}

func listObjects(basedir string) {
	// Below does not work because currently Glob does not support ./**/*
	//list, err := filepath.Glob(basedir + string(filepath.Separator) + *_FILTER)
	// Somehow WalkDir is slower in this code
	//err := filepath.WalkDir(basedir, func(path string, f fs.DirEntry, err error) error {
	err := filepath.Walk(basedir, func(path string, f os.FileInfo, err error) error {
		if err != nil {
			return errors.Wrap(err, "failed filepath.WalkDir")
		}
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
	_PREFIX = flag.String("p", "", "Prefix of sub directories (eg: vol-)")
	_FILTER = flag.String("f", "", "Filter string for file paths (eg: .properties)")
	_FILTER2 = flag.String("fP", "", "Filter string for properties (-P is required)")
	_TOP_N = flag.Int64("n", 0, "Return only first N keys (0 = no limit)")
	_CONC_1 = flag.Int("c", 1, "Concurrent number for sub directories (may not need to use with very fast disk)")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
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
		_log("ERROR", "-c is lower than 1.")
		os.Exit(1)
	}

	if !*_NO_HEADER {
		fmt.Print("Path,LastModified,Size")
		if *_WITH_PROPS {
			fmt.Print(",Properties")
		}
		fmt.Println("")
	}

	_log("DEBUG", fmt.Sprintf("Retriving sub directories under %s", *_BASEDIR))
	subDirs := getDirs(*_BASEDIR, *_PREFIX)
	if *_LIST_DIRS {
		fmt.Printf("%v", subDirs)
		return
	}
	_log("DEBUG", fmt.Sprintf("Sub directories: %v", subDirs))

	_log("INFO", fmt.Sprintf("Generating list from %s ...", *_BASEDIR))
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
