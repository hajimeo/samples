package helpers

import (
	"log"
	"os"
)

var _DEBUG bool

func uLog(level string, message string) {
	if level != "DEBUG" || _DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func uEnv(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func uEnvB(key string, fallback bool) bool {
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
