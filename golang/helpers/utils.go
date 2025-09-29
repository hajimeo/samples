package helpers

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

var DEBUG bool
var DEBUG_FNAME_SKIP_LEVEL int = 1 // skip the first level of the caller's function name, which is this function

func CaptureStderr(f func()) string {
	/* output := CaptureStderr(func() { PrintErr(err) }) */
	old := os.Stderr
	r, w, _ := os.Pipe() // read, write, error
	os.Stderr = w        // redirect stderr to w
	f()                  // call the function
	w.Close()
	os.Stderr = old
	var buf bytes.Buffer
	io.Copy(&buf, r) // copy the output from r to buf
	return buf.String()
}

func CaptureStdout(f func()) string {
	/* output := CaptureStdout(func() { PrintOut(line) }) */
	old := os.Stdout
	r, w, _ := os.Pipe() // read, write, error
	os.Stdout = w        // redirect stderr to w
	f()                  // call the function
	w.Close()
	os.Stdout = old
	var buf bytes.Buffer
	io.Copy(&buf, r) // copy the output from r to buf
	return buf.String()
}

func Log(level string, message interface{}) {
	// only if DEBUG, get the caller's method name and line number and append to the message
	if DEBUG {
		pc, _, line, ok := runtime.Caller(DEBUG_FNAME_SKIP_LEVEL)
		if ok {
			fn := runtime.FuncForPC(pc)
			if fn != nil {
				message = fmt.Sprintf("[%s:%d] %v", fn.Name(), line, message)
			}
		}
	}

	if level != "DEBUG" || DEBUG {
		log.Printf("[%s] %v\n", level, message)
	}
}

func Elapsed(startTsMs int64, message string, thresholdMs int64) {
	//elapsed := time.Since(start)
	elapsed := time.Now().UnixMilli() - startTsMs
	label := "INFO"
	if thresholdMs > 0 {
		label = "WARN"
	}
	if elapsed >= thresholdMs {
		Log(label, fmt.Sprintf("%s (%d ms)", message, elapsed))
	}
}

func PrintErr(err interface{}) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
	}
}

func TruncateStr(s string, maxLength int) string {
	if len(s) <= maxLength {
		return s
	}
	return s[:maxLength] + "..."
}

func AppendSlash(dirPath string) string {
	return AppendChar(dirPath, string(filepath.Separator))
}

func AppendChar(dirPath string, c string) string {
	// If empty, not appending character
	if len(dirPath) == 0 {
		return dirPath
	}
	return strings.TrimSuffix(dirPath, c) + c
}

func PathWithoutExt(path string) string {
	return path[:len(path)-len(filepath.Ext(path))]
}

func DatetimeStrToInt(datetimeStr string) int64 {
	if len(datetimeStr) == 0 {
		panic("datetimeStr is empty")
	}
	if IsNumeric(datetimeStr) {
		i64, err := strconv.ParseInt(datetimeStr, 10, 64)
		if err != nil {
			panic(err)
		}
		return i64
	}
	if len(datetimeStr) <= 10 {
		datetimeStr = datetimeStr + " 00:00:00"
	}
	tmpTimeFrom, err := time.Parse("2006-01-02 15:04:03", datetimeStr)
	if err != nil {
		panic(err)
	}
	return tmpTimeFrom.Unix()
}

func ValsToString(vals []interface{}, delimiter string) string {
	strSlice := make([]string, len(vals))
	for i, val := range vals {
		strSlice[i] = fmt.Sprint(val)
	}
	result := strings.Join(strSlice, delimiter)
	return result
}

func GetEnv(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func SetEnv(key string, value string) {
	if len(key) == 0 {
		return
	}
	err := os.Setenv(key, value)
	PanicIfErr(err)
}

func GetEnvInt(key string, fallback int) int {
	value, exists := os.LookupEnv(key)
	if exists {
		i64, err := strconv.Atoi(value)
		PanicIfErr(err)
		return i64
	}
	return fallback
}

func GetEnvInt64(key string, fallback int64) int64 {
	value, exists := os.LookupEnv(key)
	if exists {
		i64, err := strconv.ParseInt(value, 10, 64)
		PanicIfErr(err)
		return i64
	}
	return fallback
}

func GetEnvBool(key string, fallback bool) bool {
	value, exists := os.LookupEnv(key)
	if exists {
		switch strings.ToLower(value) {
		case
			"true",
			"y",
			"yes":
			return true
		}
	}
	return fallback
}

func GetBoolEnv(key string, fallback bool) bool {
	return GetEnvBool(key, fallback)
}

func IsNumeric(obj interface{}) bool {
	s := fmt.Sprintf("%v", obj)
	_, err := strconv.ParseFloat(s, 64)
	return err == nil
}

func IsEmpty(obj interface{}) bool {
	if obj == nil {
		return true
	}
	s := fmt.Sprintf("%v", obj)
	s = strings.TrimSpace(s)
	if s == "" || s == "0" || s == "[]" || s == "map[]" {
		// currently 0 is treated as empty, but somehow 0.0 works
		return true
	}
	return false
}

func DeferPanic() {
	// Use this function with 'defer' to recover from panic if occurred. Set err to nil otherwise.
	if r := recover(); r != nil {
		log.Println("Panic occurred:", r)
	}
}

func PanicIfErr(err error) {
	if err != nil {
		panic(err)
	}
}

func Chunk(slice []string, chunkSize int) [][]string {
	// Split a slice into chunks
	var chunks [][]string
	for i := 0; i < len(slice); i += chunkSize {
		end := i + chunkSize
		if end > len(slice) {
			end = len(slice)
		}
		chunks = append(chunks, slice[i:end])
	}
	return chunks
}

func Distinct[T any](a []T) (obj []any) {
	// Remove duplicates from a slice (or any object)
	u := make(map[any]bool)
	for _, val := range a {
		if _, ok := u[val]; !ok {
			obj = append(obj, val)
			u[val] = true
		}
	}
	return
}

type StoreProps map[string]string

func ReadPropertiesFile(path string) (StoreProps, error) {
	props := StoreProps{}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if equal := strings.Index(line, "="); equal >= 0 {
			if key := strings.TrimSpace(line[:equal]); len(key) > 0 {
				value := ""
				if len(line) > equal {
					value = strings.TrimSpace(line[equal+1:])
				}
				props[key] = value
			}
		}
	}
	if err = scanner.Err(); err != nil {
		return nil, err
	}
	return props, nil
}

func OpenStdInOrFIle(path string) *os.File {
	f := os.Stdin
	if path != "-" {
		var err error
		f, err = os.Open(path)
		if err != nil {
			Log("ERROR", "path:"+path+" cannot be opened. "+err.Error())
			return nil
		}
	}
	return f
}

func StreamLines(path string, conc int, apply func(string) interface{}) []interface{} {
	var returns []interface{}
	input := make(chan string, conc)

	// Open the file from the path
	fp := OpenStdInOrFIle(path)
	defer fp.Close()
	scanner := bufio.NewScanner(fp)

	go func() {
		for scanner.Scan() {
			input <- scanner.Text()
		}
		close(input)
	}()

	var wg sync.WaitGroup
	for i := 0; i < conc; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for line := range input {
				returns = append(returns, apply(line))
				//time.Sleep(100 * time.Millisecond) // for test
			}
		}()
	}

	//close(input) // no need to close as closed in the first go func
	wg.Wait()
	// TODO: as per AI, using returns is not thread safe, and it's not used anyway
	return returns
}

var (
	_cachedObjects = make(map[string]interface{})
	_mu            sync.RWMutex
)

func CacheGetObj(key string) interface{} {
	_mu.RLock()
	defer _mu.RUnlock()
	value, exists := _cachedObjects[key]
	if exists {
		return value
	}
	return nil
}

func CacheAddObject(key string, value interface{}, maxSize int) {
	_mu.Lock()
	for k := range _cachedObjects {
		// Because going to add one, using >= (
		if len(_cachedObjects) >= maxSize {
			// NOTE: to be safe, should it create a copy of _cachedObjects?
			delete(_cachedObjects, k)
		} else {
			break
		}
	}
	_cachedObjects[key] = value
	_mu.Unlock()
}

func CacheDelObj(key string) {
	_mu.Lock()
	delete(_cachedObjects, key)
	_mu.Unlock()
}
