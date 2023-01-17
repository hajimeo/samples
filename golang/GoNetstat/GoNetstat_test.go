package main

import (
	"os"
	"strings"
	"testing"
)

var DUMMY_LINE = "   0: 00000000:A41D 00000000:0000 0A 00000001:00000002 00:00000000 00000000     0        0 45079 1 ffff930accdbf1c0 100 0 0 10 0"

func TestMain(m *testing.M) {
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestRemoveEmpty(t *testing.T) {
	l := removeEmpty(strings.Split(strings.TrimSpace(DUMMY_LINE), " "))
	if l == nil {
		t.Errorf("Empty removed line should not be empty.")
	} else {
		t.Logf("line_array: %s", l)
	}
}

func TestPadStrToDec(t *testing.T) {
	d := padStrToDec("00000050")
	if d != 50 {
		t.Errorf("00000050 should be 50, but got %v", d)
	}
	d = padStrToDec("aaaaa")
	if d != -1 {
		t.Errorf("aaaaa should be -1, but got %v", d)
	}
}

func TestPrintSocket(t *testing.T) {
	header := genHeader()
	t.Logf("%s", header)
	s := Socket{"uid", "name", "pid", "test.exe", "TEST", "1.2.3.4", 5678, "5.6.7.8", 10001, "inode", 12345, 54321, "timeout"}
	line := genPrintLine(s, "tcp")
	t.Logf("%s", line)
	if len(header) != len(line) {
		t.Errorf("Length of header and line should be same")
	}
}
