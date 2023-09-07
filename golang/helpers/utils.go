package helpers

import (
	"bufio"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

var DEBUG bool

func Log(level string, message interface{}) {
	if level != "DEBUG" || DEBUG {
		log.SetPrefix(time.Now().Format("2006-01-02 15:04:05") + " [" + level + "] ")
		log.Printf("%v\n", level, message)
	}
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

func GetBoolEnv(key string, fallback bool) bool {
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

func DeferPanic() {
	// recover from panic if one occurred. Set err to nil otherwise.
	if err := recover(); err != nil {
		log.Println("Panic occurred:", err)
	}
}

func PanicIfErr(err error) {
	if err != nil {
		panic(err)
	}
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
