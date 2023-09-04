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
	ascii := asciiChart("00:00:00,000", 10000, 10000)
	if len(ascii) > 0 {
		t.Errorf("With DIVIDE_MS_DEFAULT, should be no ascii")
		return
	}
	ascii = asciiChart("00:00:00,000", 10000*2, 10000)
	if len(ascii) == 0 {
		t.Errorf("No ascii string generated")
		return
	}
	//t.Logf(ascii)
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
func TestEchoDuration(t *testing.T) {
	echoDuration("end line")
	t.Log("TODO: not implemented")
	return
}
func TestEchoDurationInner(t *testing.T) {
	t.Log("TODO: not implemented")
	return
}
func TestechoDurations(t *testing.T) {
	t.Log("TODO: not implemented")
	return
}
func TestEchoEndLine(t *testing.T) {
	echoEndLine("end line", NO_KEY)
	t.Log("TODO: not implemented")
	return
}
func TestEchoStartLine(t *testing.T) {
	echoStartLine("start line", NO_KEY)
	t.Log("TODO: not implemented")
	return
}
func TestEchoLine(t *testing.T) {
	shouldBeTrue := echoLine("end line", nil)
	if !shouldBeTrue {
		t.Errorf("echoLine should be always return true")
		return
	}
}
func TestGetKey(t *testing.T) {
	shouldBeNoKey := getKey("end line")
	if shouldBeNoKey != NO_KEY {
		t.Errorf("NO_KEY should be returned")
		return
	}
}
func TestRemoveHTML(t *testing.T) {
	noHTMLLine := removeHTML("no html line")
	if noHTMLLine != "no html line" {
		t.Errorf("line should not be changed")
		return
	}
	HTMLLine := removeHTML("<html> line")
	//t.Logf(HTMLLine)
	if HTMLLine != " line" {
		t.Errorf("line should be changed")
		return
	}
}
func TestSetStartDatetimeFromLine(t *testing.T) {
	t.Log("TODO: not implemented")
	return
}
func TestProcessFile(t *testing.T) {
	t.Log("TODO: not implemented")
	return
}
