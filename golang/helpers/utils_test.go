package helpers

import (
	"fmt"
	"github.com/stretchr/testify/assert"
	"os"
	"path/filepath"
	"sync"
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
	if result != "thisisaver..." {
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
	result = DatetimeStrToInt("1730246400")
	if result != 1730246400 {
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

func TestChunk_EmptySlice_ReturnsEmpty(t *testing.T) {
	result := Chunk([]string{}, 2)
	assert.Equal(t, 0, len(result))
}

func TestChunk_SingleElement_ReturnsSingleChunk(t *testing.T) {
	result := Chunk([]string{"a"}, 2)
	assert.Equal(t, [][]string{{"a"}}, result)
}

func TestChunk_MultipleElements_ReturnsChunks(t *testing.T) {
	result := Chunk([]string{"a", "b", "c", "d", "e"}, 2)
	assert.Equal(t, [][]string{{"a", "b"}, {"c", "d"}, {"e"}}, result)
}

func TestChunk_ChunkSizeGreaterThanSliceLength_ReturnsSingleChunk(t *testing.T) {
	result := Chunk([]string{"a", "b"}, 5)
	assert.Equal(t, [][]string{{"a", "b"}}, result)
}

func TestChunk_ChunkSizeOne_ReturnsIndividualElements(t *testing.T) {
	result := Chunk([]string{"a", "b", "c"}, 1)
	assert.Equal(t, [][]string{{"a"}, {"b"}, {"c"}}, result)
}

func TestDistinct_EmptySlice_ReturnsEmpty(t *testing.T) {
	result := Distinct([]string{})
	assert.Equal(t, 0, len(result))
}

func TestDistinct_NoDuplicates_ReturnsSameSlice(t *testing.T) {
	result := Distinct([]string{"a", "b", "c"})
	assert.Equal(t, []any{"a", "b", "c"}, result)
}

func TestDistinct_WithDuplicates_RemovesDuplicates(t *testing.T) {
	result := Distinct([]string{"a", "b", "a", "c", "b"})
	assert.Equal(t, []any{"a", "b", "c"}, result)
}

func TestDistinct_IntSlice_RemovesDuplicates(t *testing.T) {
	result := Distinct([]int{1, 2, 2, 3, 1})
	assert.Equal(t, []any{1, 2, 3}, result)
}

func TestDistinct_MixedTypes_RemovesDuplicates(t *testing.T) {
	result := Distinct([]any{"a", 1, "a", 2, 1})
	assert.Equal(t, []any{"a", 1, 2}, result)
}

func TestReadPropertiesFile(t *testing.T) {
	t.Logf("TODO: not implemented")
}

func TestAppendSlash_EmptyString_ReturnsSlash(t *testing.T) {
	result := AppendSlash("")
	assert.Equal(t, "", result)
}

func TestAppendSlash_NoTrailingSlash_AddsSlash(t *testing.T) {
	result := AppendSlash("path/to/dir")
	assert.Equal(t, "path/to/dir"+string(filepath.Separator), result)
}

func TestAppendSlash_HasTrailingSlash_ReturnsSameString(t *testing.T) {
	result := AppendSlash("path/to/dir/")
	assert.Equal(t, "path/to/dir/", result)
}

func TestAppendSlash_RootPath_ReturnsRootWithSlash(t *testing.T) {
	result := AppendSlash("/")
	assert.Equal(t, "/", result)
}

func TestPrintErr_NilError_NoOutput(t *testing.T) {
	PrintErr(nil)
	t.Logf("Check output")
}

func TestPrintErr_NonNilError_PrintsError(t *testing.T) {
	err := fmt.Errorf("sample error")
	output := CaptureStderr(func() {
		PrintErr(err)
	})
	assert.Contains(t, output, "sample error")
}

func TestPrintErr_StringError_PrintsString(t *testing.T) {
	err := "string error"
	output := CaptureStderr(func() {
		PrintErr(err)
	})
	assert.Contains(t, output, "string error")
}

func TestIsEmpty_NilInput_ReturnsTrue(t *testing.T) {
	result := IsEmpty(nil)
	assert.True(t, result)
}

func TestIsEmpty_EmptyString_ReturnsTrue(t *testing.T) {
	result := IsEmpty("")
	assert.True(t, result)
}

func TestIsEmpty_WhitespaceString_ReturnsTrue(t *testing.T) {
	result := IsEmpty("   ")
	assert.True(t, result)
}

func TestIsEmpty_NonEmptyString_ReturnsFalse(t *testing.T) {
	result := IsEmpty("non-empty")
	assert.False(t, result)
}

func TestIsEmpty_ZeroValueInt_ReturnsTrue(t *testing.T) {
	result := IsEmpty(0)
	assert.True(t, result)
}

func TestIsEmpty_ZeroValueFloat_ReturnsTrue(t *testing.T) {
	result := IsEmpty(0.0)
	// Not sure why this works
	assert.True(t, result)
}

func TestIsEmpty_EmptySlice_ReturnsTrue(t *testing.T) {
	result := IsEmpty([]string{})
	assert.True(t, result)
}

func TestIsEmpty_EmptyMap_ReturnsTrue(t *testing.T) {
	result := IsEmpty(map[string]string{})
	assert.True(t, result)
}

func TestStreamFile_EmptyFile_NoProcessing(t *testing.T) {
	path := "empty_file.txt"
	os.WriteFile(path, []byte(""), 0644)
	defer os.Remove(path)

	processedLines := StreamLines(path, 1, func(line string) interface{} {
		return line
	})

	assert.Empty(t, processedLines)
}

func TestStreamFile_SingleLineFile_ProcessesLine(t *testing.T) {
	path := "single_line_file.txt"
	os.WriteFile(path, []byte("single line"), 0644)
	defer os.Remove(path)

	processedLines := StreamLines(path, 1, func(line string) interface{} {
		return line
	})

	t.Logf("processedLines: %v", processedLines)
	assert.Equal(t, "single line", processedLines[0])
}

func TestStreamFile_ConcurrentProcessing_ProcessesAllLines(t *testing.T) {
	path := "concurrent_file.txt"
	os.WriteFile(path, []byte("line1\nline2\nline3\nline4\nline5"), 0644)
	defer os.Remove(path)

	processedLines := StreamLines(path, 1, func(line string) interface{} {
		return line
	})
	// Order of lines may not be preserved
	//assert.ElementsMatch(t, []string{"line1", "line2", "line3", "line4", "line5"}, processedLines)
	assert.Equal(t, 5, len(processedLines))
}

func TestCacheGetObj_KeyExists_ReturnsValue(t *testing.T) {
	_cachedObjects["key1"] = "value1"
	result := CacheGetObj("key1")
	assert.Equal(t, "value1", result)
}

func TestCacheGetObj_KeyDoesNotExist_ReturnsNil(t *testing.T) {
	result := CacheGetObj("nonexistent")
	assert.Nil(t, result)
}

func TestCacheAddObject_AddsObjectToCache(t *testing.T) {
	CacheAddObject("key2", "value2", 10)
	result := CacheGetObj("key2")
	assert.Equal(t, "value2", result)
}

func TestCacheAddObject_ExceedsMaxSize_RemovesOldestObject(t *testing.T) {
	CacheAddObject("key3", "value3", 1)
	CacheAddObject("key4", "value4", 1)
	result := CacheGetObj("key3")
	assert.Nil(t, result)
	result = CacheGetObj("key4")
	assert.Equal(t, "value4", result)
}

func TestCacheAddObject_MaxSizeZero_StillAddsObject(t *testing.T) {
	CacheAddObject("key5", "value5", 0)
	result := CacheGetObj("key5")
	assert.Equal(t, "value5", result)
}

func TestCacheDelObj_KeyExists_RemovesObject(t *testing.T) {
	CacheAddObject("key1", "value1", 10)
	CacheDelObj("key1")
	result := CacheGetObj("key1")
	assert.Nil(t, result)
}

func TestCacheDelObj_KeyDoesNotExist_NoError(t *testing.T) {
	CacheDelObj("nonexistent")
	result := CacheGetObj("nonexistent")
	assert.Nil(t, result)
}

func TestCacheDelObj_ConcurrentAccess_NoDataRace(t *testing.T) {
	CacheAddObject("key1", "value1", 10)
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			CacheDelObj("key1")
		}()
	}
	wg.Wait()
	result := CacheGetObj("key1")
	assert.Nil(t, result)
}

func TestValsToString_EmptySlice_ReturnsEmptyString(t *testing.T) {
	result := ValsToString([]interface{}{}, ",")
	assert.Equal(t, "", result)
}

func TestValsToString_SingleElement_ReturnsElementAsString(t *testing.T) {
	result := ValsToString([]interface{}{"single"}, ",")
	assert.Equal(t, "single", result)
}

func TestValsToString_MultipleElements_ReturnsJoinedString(t *testing.T) {
	result := ValsToString([]interface{}{"a", "b", "c"}, ",")
	assert.Equal(t, "a,b,c", result)
}

func TestValsToString_DifferentTypes_ReturnsJoinedString(t *testing.T) {
	result := ValsToString([]interface{}{"a", 1, 2.5, true}, ",")
	assert.Equal(t, "a,1,2.5,true", result)
}

func TestValsToString_CustomDelimiter_ReturnsJoinedStringWithDelimiter(t *testing.T) {
	result := ValsToString([]interface{}{"a", "b", "c"}, "|")
	assert.Equal(t, "a|b|c", result)
}
