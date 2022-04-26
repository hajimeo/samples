package helpers

import (
	"log"
	"os"
)

var DEBUG bool

func ULog(level string, message string) {
	if level != "DEBUG" || DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func UEnv(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func UEnvB(key string, fallback bool) bool {
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
