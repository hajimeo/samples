package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
)

func usage() {
	fmt.Println(`
Connect to PostgreSQL and return the result based on the command arguments
    
HOW-TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/NexusSql/README.md
`)
	flag.PrintDefaults()
}

// Arguments
var _APPTYPE *string
var _ACTION *string
var _CONFIG *string
var _DEBUG *bool

func _setGlobals() {
	_APPTYPE = flag.String("t", "nxrm", "Application Type [nxrm|nxiq] Default is nxrm")
	_ACTION = flag.String("a", "", "empty for all or [db-check|data-size|data-export]")
	_CONFIG = flag.String("c", "./", "Path to DB connection config file (nexus-store.properties or config.yml")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	flag.Parse()
}

func _log(level string, message string) {
	if level != "DEBUG" || *_DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

type AppConfigProperties map[string]string

func readPropertiesFile(filename string) (AppConfigProperties, error) {
	config := AppConfigProperties{}

	if len(filename) == 0 {
		return config, nil
	}
	file, err := os.Open(filename)
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
				config[key] = value
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return config, nil
}

func buildConnStringFromFileForNXRM(filePath string) string {
	config, err := readPropertiesFile(filePath)
	if err != nil {
		_log("ERROR", err.Error())
		return ""
	}
	// jdbcUrl=jdbc\:postgresql\://192.168.1.31\:5432/nxrm3pg	// Expecting removing \ first
	jdbcPtn := regexp.MustCompile(`jdbc:postgresql:([^/]+)/([^?]+)\??(.*)`)
	matches := jdbcPtn.FindStringSubmatch(strings.ReplaceAll(config["jdbcUrl"], "\\", ""))
	if matches == nil {
		_log("ERROR", "No 'jdbcUrl' in "+filePath)
		return ""
	}
	hostname := matches[1]
	database := matches[2]
	params := ""
	if len(matches) > 2 {
		params = matches[3]
		params = " " + strings.ReplaceAll(params, "&", " ")
	}
	return fmt.Sprintf("host=%s user=%s password=%s dbname=%s%s", hostname, config["username"], config["password"], database, params)
}

func buildConnStringForNXRM(config AppConfigProperties) (string, error) {
	// jdbcUrl=jdbc\:postgresql\://192.168.1.31\:5432/nxrm3pg	// Expecting removing \ first
	jdbcPtn := regexp.MustCompile(`jdbc:postgresql:([^/]+)/([^?]+)\??(.*)`)
	matches := jdbcPtn.FindStringSubmatch(strings.ReplaceAll(config["jdbcUrl"], "\\", ""))
	if matches == nil {
		_log("ERROR", "No 'jdbcUrl' in "+filePath)
		return ""
	}
	hostname := matches[1]
	database := matches[2]
	params := ""
	if len(matches) > 2 {
		params = matches[3]
		params = " " + strings.ReplaceAll(params, "&", " ")
	}
	return fmt.Sprintf("host=%s user=%s password=%s dbname=%s%s", hostname, config["username"], config["password"], database, params)
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}
	_setGlobals()
}
