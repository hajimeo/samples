package helpers

import (
	"log"
	"os"
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
