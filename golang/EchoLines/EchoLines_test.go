package main

import (
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	// Write code here to run before tests
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestAsciiChart(t *testing.T) {
	ascii := asciiChart("00:00:00,000", DIVIDE_MS_DEFAULT)
	if len(ascii) > 0 {
		t.Errorf("With DIVIDE_MS_DEFAULT, should be no ascii")
		return
	}
	ascii = asciiChart("00:00:00,000", DIVIDE_MS_DEFAULT*2)
	if len(ascii) == 0 {
		t.Errorf("No ascii string generated")
		return
	}
	//t.Log(ascii)
}
func TestCalcDurationFromStrings(t *testing.T) {
	duration := calcDurationFromStrings("00:00:00,000", "00:00:00,001")
	if duration.Milliseconds() != 1 {
		t.Errorf("Duration should be 1 ms")
		return
	}
	ELAPSED_FORMAT = ""
	duration = calcDurationFromStrings("2020-10-20 00:00:00,000", "2020-10-21 00:00:00,000")
	if duration.Hours() != 24 {
		t.Errorf("Duration should be 24 hours")
		return
	}
}
