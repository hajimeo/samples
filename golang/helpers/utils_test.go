package helpers

import (
	"fmt"
	"os"
	"testing"
	"time"
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

func TestElapsed(t *testing.T) {
	startMs := time.Now().UnixMilli()
	Elapsed(startMs, fmt.Sprintf("TEST startMs = %d", startMs), 0)
}

func TestTruncateStr_StringShorterThanMaxLength_ReturnsOriginal(t *testing.T) {
	result := TruncateStr("short", 10)
	if result != "short" {
		t.Errorf("Expected 'short' but got %v", result)
	}
}

func TestTruncateStr_StringEqualToMaxLength_ReturnsOriginal(t *testing.T) {
	result := TruncateStr("exactlength", 11)
	if result != "exactlength" {
		t.Errorf("Expected 'exactlength' but got %v", result)
	}
}

func TestTruncateStr_StringLongerThanMaxLength_ReturnsTruncated(t *testing.T) {
	result := TruncateStr("thisisaverylongstring", 10)
	if result != "thisisaver" {
		t.Errorf("Expected 'thisisaver' but got %v", result)
	}
}

func TestDatetimeStrToInt(t *testing.T) {
	result := DatetimeStrToInt("2023-10-20")
	if result != 1697760000 {
		t.Errorf("Result should be timestanmp (int64) but got %v", result)
	}
	result = DatetimeStrToInt("2023-10-20 12:12:12")
	if result != 1697803920 {
		t.Errorf("Result should be timestanmp (int64) but got %v", result)
	}
	//result = datetimeStrToTs("aaaaa")
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
	shouldBeInt := GetEnvInt("FOO2", 2)
	if shouldBeInt != 2 {
		t.Errorf("Result should be 2")
	}
	var i64 int64 = 2
	shouldBeI64 := GetEnvInt64("FOO2", i64)
	if shouldBeI64 != i64 {
		t.Errorf("Result should be 2")
	}
	shouldBeTrue := GetBoolEnv("FOO_BOOL", true)
	if !shouldBeTrue {
		t.Errorf("Result should be true")
	}
	os.Setenv("FOO_BOOL", "Y")
	shouldBeTrue = GetBoolEnv("FOO_BOOL", true)
	if !shouldBeTrue {
		t.Errorf("Result should be true")
	}
	os.Setenv("FOO_BOOL", "y")
	shouldBeTrue = GetBoolEnv("FOO_BOOL", true)
	if !shouldBeTrue {
		t.Errorf("Result should be true")
	}
}

func TestIsNumeric_ValidNumber_ReturnsTrue(t *testing.T) {
	if !IsNumeric(123) {
		t.Errorf("Expected true for numeric input")
	}
	if !IsNumeric(123.45) {
		t.Errorf("Expected true for numeric input")
	}
	if !IsNumeric("123") {
		t.Errorf("Expected true for numeric input")
	}
	if !IsNumeric("123.45") {
		t.Errorf("Expected true for numeric input")
	}
}

func TestIsNumeric_InvalidNumber_ReturnsFalse(t *testing.T) {
	if IsNumeric("abc") {
		t.Errorf("Expected false for non-numeric input")
	}
	if IsNumeric("123abc") {
		t.Errorf("Expected false for non-numeric input")
	}
	if IsNumeric(nil) {
		t.Errorf("Expected false for nil input")
	}
	if IsNumeric(true) {
		t.Errorf("Expected false for boolean input")
	}
}

func TestUniqueSlice(t *testing.T) {
	s := []string{"aaaa", "bbbb", "cccc", "bbbb", "dddd", "aaaa"}
	rtn := UniqueSlice(s)
	if len(rtn) != 4 {
		t.Errorf("Result length should be 4 but got %d (%v)", len(rtn), rtn)
	}
	i := []int{1, 2, 3, 2, 5, 1}
	rtn = UniqueSlice(i)
	if len(rtn) != 4 {
		t.Errorf("Result length should be 4 but got %d (%v)", len(rtn), rtn)
	}
	//t.Logf("type: %T, value:%v", rtn, rtn)
}

func TestReadPropertiesFile(t *testing.T) {
	t.Logf("TODO: not implemented")
}
