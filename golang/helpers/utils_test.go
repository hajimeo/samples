package helpers

import (
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestLog(t *testing.T) {
	Log("DEBUG", "DEBUG logging")
}

func TestGetEnv(t *testing.T) {
	os.Setenv("FOO", "1")
	shouldBe1 := GetEnv("FOO", "2")
	if shouldBe1 != "1" {
		t.Errorf("Result should be 1")
	}
	shouldBe2 := GetEnv("FOO2", "2")
	if shouldBe2 != "2" {
		t.Errorf("Result should be 2")
	}
	shouldBeInt := GetEnvInt64("FOO2", 2)
	if shouldBeInt != 2 {
		t.Errorf("Result should be 2")
	}
	var i64 int64 = 2
	shouldBeI64 := GetEnvInt64("FOO2", i64)
	if shouldBeI64 != i64 {
		t.Errorf("Result should be 2")
	}
	shouldBeTrue := GetBoolEnv("FOO2", true)
	if !shouldBeTrue {
		t.Errorf("Result should be true")
	}
}

func TestReadPropertiesFile(t *testing.T) {
	t.Logf("TODO: not implemented")
}
