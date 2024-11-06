package helpers

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var DEBUG bool

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
	return s[:maxLength]
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

func GetEnv(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
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
