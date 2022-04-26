package helpers

import (
	"log"
	"os"
)

var _DEBUG bool

func _log(level string, message string) {
	if level != "DEBUG" || _DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func _env(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func _envB(key string, fallback bool) bool {
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
