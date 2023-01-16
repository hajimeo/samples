package main

import (
	"os"
	"strings"
	"testing"
)

func TestMain(m *testing.M) {
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestRemoveEmpty(t *testing.T) {
	line := "   0: 00000000:A41D 00000000:0000 0A 00000001:00000002 00:00000000 00000000     0        0 45079 1 ffff930accdbf1c0 100 0 0 10 0"
	line_array := removeEmpty(strings.Split(strings.TrimSpace(line), " "))
	if line_array == nil {
		t.Errorf("DB connection props should not be empty")
	} else {
		t.Errorf("line_array: %s", line_array)
	}
}
