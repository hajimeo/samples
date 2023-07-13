package helpers

import (
	"bufio"
	"log"
	"os"
	"strings"
)

var DEBUG bool

func Log(level string, message string) {
	if level != "DEBUG" || DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func getEnv(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func getBoolEnv(key string, fallback bool) bool {
	value, exists := os.LookupEnv(key)
	if exists {
		switch value {
		case
			"TRUE",
			"True",
			"true",
			"Y",
			"Yes",
			"YES":
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

func readPropertiesFile(path string) (StoreProps, error) {
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
