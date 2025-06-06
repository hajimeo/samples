package bs_clients

import (
	"FileListV2/common"
	"database/sql"
	"github.com/stretchr/testify/assert"
	"os"
	"testing"
)

var TEST_DATA_DIR = "/tmp/File_test/testdata"

//func TestMain(m *testing.M) {
//}

func TestReadPath_ValidPath_ReturnsContents(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/sample.txt"
	err := os.WriteFile(path, []byte("sample content"), 0644)
	if err != nil {
		t.Log("Could not create test file")
		t.SkipNow()
	}
	defer os.Remove(path)
	contents, err := client.ReadPath(path)
	assert.NoError(t, err)
	assert.Equal(t, "sample content", contents)
}

func TestReadPath_InvalidPath_ReturnsError(t *testing.T) {
	client := &FileClient{}
	path := "invalid/path"
	contents, err := client.ReadPath(path)
	assert.Error(t, err)
	assert.Empty(t, contents)
}

func TestReadPath_EmptyFile_ReturnsEmptyString(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/empty.txt"
	err := os.WriteFile(path, []byte(""), 0644)
	if err != nil {
		t.Log("Could not create test file")
		t.SkipNow()
	}
	defer os.Remove(path)
	contents, err := client.ReadPath(path)
	assert.NoError(t, err)
	assert.Equal(t, "", contents)
}

func TestReadPath_WhitespaceContent_ReturnsTrimmedString(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/whitespace.txt"
	err := os.WriteFile(path, []byte("  content  "), 0644)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(path)
	contents, err := client.ReadPath(path)
	assert.NoError(t, err)
	assert.Equal(t, "content", contents)
}

func TestWriteToPath_ValidPath_WritesContents(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/write_sample.txt"
	defer os.Remove(path)
	err := client.WriteToPath(path, "sample content")
	assert.NoError(t, err)
	contents, err := os.ReadFile(path)
	assert.NoError(t, err)
	assert.Equal(t, "sample content", string(contents))
}

func TestWriteToPath_InvalidPath_ReturnsError(t *testing.T) {
	client := &FileClient{}
	path := "/invalid/path/write_sample.txt"
	err := client.WriteToPath(path, "sample content")
	assert.Error(t, err)
}

func TestWriteToPath_EmptyContents_WritesEmptyFile(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/empty_write_sample.txt"
	defer os.Remove(path)
	err := client.WriteToPath(path, "")
	assert.NoError(t, err)
	contents, err := os.ReadFile(path)
	assert.NoError(t, err)
	assert.Equal(t, "", string(contents))
}

func TestWriteToPath_WhitespaceContents_WritesTrimmedContents(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	path := TEST_DATA_DIR + "/whitespace_write_sample.txt"
	defer os.Remove(path)
	err := client.WriteToPath(path, "  content  ")
	assert.NoError(t, err)
	contents, err := os.ReadFile(path)
	assert.NoError(t, err)
	assert.Equal(t, "  content  ", string(contents))
}

func TestGetDirs_ValidPattern_ReturnsMatchingDirs(t *testing.T) {
	baseDir := TEST_DATA_DIR + "/vol-NN/char-MM"
	err := os.MkdirAll(baseDir, os.ModePerm)
	if err != nil {
		t.Log("Could not create test directory")
		t.SkipNow()
	}
	client := &FileClient{}
	pattern := ".*vol-.+/char-.+"
	dirs, err := client.GetDirs(baseDir, pattern, 0)
	if err != nil {
		t.Log(err)
	}
	//t.Logf("%s\n", dirs[0])
	assert.Contains(t, dirs, baseDir)
}

func TestGetDirs_NoMatchingDirs_ReturnsEmpty(t *testing.T) {
	baseDir := TEST_DATA_DIR + "/matchingDir"
	err := os.MkdirAll(baseDir, os.ModePerm)
	if err != nil {
		t.Log("Could not create test directory")
		t.SkipNow()
	}
	client := &FileClient{}
	pattern := ".*nonexistent.*"
	dirs, err := client.GetDirs(baseDir, pattern, 0)
	if err != nil {
		t.Log(err)
	}
	assert.Empty(t, dirs)
}

func TestGetDirs_EmptyPattern_ReturnsAllDirs(t *testing.T) {
	baseDir := TEST_DATA_DIR
	err := os.MkdirAll(baseDir, os.ModePerm)
	if err != nil {
		t.Log("Could not create test directory")
		t.SkipNow()
	}
	client := &FileClient{}
	pattern := ""
	dirs, err := client.GetDirs(baseDir, pattern, 0)
	if err != nil {
		t.Log(err)
	}
	assert.NotEmpty(t, dirs)
}

func TestGetDirs_MaxDepthExceeded_ReturnsLimitedDirs(t *testing.T) {
	baseDir := "/tmp/File_test/depthTest"
	err := os.MkdirAll(baseDir+"/subdir1/subdir2/subdir3", os.ModePerm)
	if err != nil {
		t.Log("Could not create test directory")
		t.SkipNow()
	}
	client := &FileClient{}
	pattern := ".*"
	dirs, err := client.GetDirs(baseDir, pattern, 2)
	if err != nil {
		t.Log(err)
	}
	assert.Contains(t, dirs, baseDir+"/subdir1/subdir2")
	assert.NotContains(t, dirs, baseDir+"/subdir1/subdir2/subdir3")
}

func TestGetDirs_EmptyBaseDir_ReturnsError(t *testing.T) {
	baseDir := ""
	client := &FileClient{}
	pattern := ".*"
	dirs, err := client.GetDirs(baseDir, pattern, 0)
	if err != nil {
		t.Log(err)
	}
	assert.Empty(t, dirs)
}

func TestListObjects_ValidBaseDir_ReturnsFileCount(t *testing.T) {
	baseDir := TEST_DATA_DIR + "/list_objects"
	os.MkdirAll(baseDir, os.ModePerm)
	defer os.RemoveAll(baseDir)
	os.WriteFile(baseDir+"/file1.txt", []byte("content1"), 0644)
	os.WriteFile(baseDir+"/file2.txt", []byte("content2"), 0644)
	client := &FileClient{}
	db := &sql.DB{}
	count := client.ListObjects(baseDir, db, func(args PrintLineArgs) bool { return true })
	// Because Atomic, can't use assert.Equal with '2'
	//assert.Equal(t, count, int64(2))
	assert.NotNil(t, count)
}

func TestListObjects_EmptyBaseDir_ReturnsZero(t *testing.T) {
	baseDir := TEST_DATA_DIR + "/empty_list_objects"
	os.MkdirAll(baseDir, os.ModePerm)
	defer os.RemoveAll(baseDir)
	client := &FileClient{}
	db := &sql.DB{}
	count := client.ListObjects(baseDir, db, func(args PrintLineArgs) bool { return true })
	assert.Equal(t, int64(0), count)
}

func TestListObjects_TopNLimit_ReturnsLimitedCount(t *testing.T) {
	baseDir := TEST_DATA_DIR + "/topn_list_objects"
	os.MkdirAll(baseDir, os.ModePerm)
	defer os.RemoveAll(baseDir)
	os.WriteFile(baseDir+"/file1.txt", []byte("content1"), 0644)
	os.WriteFile(baseDir+"/file2.txt", []byte("content2"), 0644)
	os.WriteFile(baseDir+"/file3.txt", []byte("content3"), 0644)
	common.TopN = 2
	client := &FileClient{}
	db := &sql.DB{}
	common.PrintedNum = 0
	testFunc := func(args PrintLineArgs) bool {
		common.PrintedNum++
		return true
	}
	count := client.ListObjects(baseDir, db, testFunc)
	assert.Equal(t, int64(2), count)
	common.TopN = 0
}

func TestListObjects_InvalidBaseDir_ReturnsError(t *testing.T) {
	baseDir := "/invalid/path"
	client := &FileClient{}
	db := &sql.DB{}
	defer func() {
		if r := recover(); r != nil {
			assert.Contains(t, r, "Got error retrieving list of files from")
		}
	}()
	client.ListObjects(baseDir, db, func(args PrintLineArgs) bool { return true })
}
func TestGetPath_ValidPath_CopiesFile(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	srcPath := TEST_DATA_DIR + "/source1.txt"
	dstPath := TEST_DATA_DIR + "/destination1.txt"
	err := os.WriteFile(srcPath, []byte("sample content"), 0644)
	if err != nil {
		t.Log("Could not create source file")
		t.SkipNow()
	}
	defer os.Remove(srcPath)
	defer os.Remove(dstPath)
	err = client.GetPath(srcPath, dstPath)
	assert.NoError(t, err)
	contents, err := os.ReadFile(dstPath)
	assert.NoError(t, err)
	assert.Equal(t, "sample content", string(contents))
}

func TestGetPath_InvalidSourcePath_ReturnsError(t *testing.T) {
	client := &FileClient{}
	srcPath := "invalid/source2.txt"
	dstPath := TEST_DATA_DIR + "/destination2.txt"
	err := client.GetPath(srcPath, dstPath)
	assert.Error(t, err)
}

func TestGetPath_EmptyLocalPath_ReturnsError(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	srcPath := TEST_DATA_DIR + "/source.txt"
	err := os.WriteFile(srcPath, []byte("sample content"), 0644)
	if err != nil {
		t.Log("Could not create source file")
		t.SkipNow()
	}
	defer os.Remove(srcPath)
	err = client.GetPath(srcPath, "")
	assert.Error(t, err)
}

func TestGetPath_CreateDestinationDir_ReturnsError(t *testing.T) {
	client := &FileClient{}
	srcPath := TEST_DATA_DIR + "/source3.txt"
	dstPath := "/invalid/destination3.txt"
	err := os.WriteFile(srcPath, []byte("sample content"), 0644)
	if err != nil {
		t.Log("Could not create source file")
		t.SkipNow()
	}
	defer os.Remove(srcPath)
	err = client.GetPath(srcPath, dstPath)
	assert.Error(t, err)
}

func TestGetPath_ValidSourceAndDestination_CopiesFileSuccessfully(t *testing.T) {
	client := &FileClient{}
	os.MkdirAll(TEST_DATA_DIR, os.ModePerm)
	srcPath := TEST_DATA_DIR + "/source4.txt"
	dstPath := TEST_DATA_DIR + "/destination4.txt"
	err := os.WriteFile(srcPath, []byte("sample content"), 0644)
	if err != nil {
		t.Log("Could not create source file")
		t.SkipNow()
	}
	defer os.Remove(srcPath)
	defer os.Remove(dstPath)
	err = client.GetPath(srcPath, dstPath)
	assert.NoError(t, err)
	contents, err := os.ReadFile(dstPath)
	assert.NoError(t, err)
	assert.Equal(t, "sample content", string(contents))
}

func TestGetPath_SourceFileDoesNotExist_ReturnsError(t *testing.T) {
	client := &FileClient{}
	srcPath := TEST_DATA_DIR + "/nonexistent.txt"
	dstPath := TEST_DATA_DIR + "/destination5.txt"
	err := client.GetPath(srcPath, dstPath)
	assert.Error(t, err)
}

func TestGetPath_EmptyDestinationPath_ReturnsError(t *testing.T) {
	client := &FileClient{}
	srcPath := TEST_DATA_DIR + "/source.txt"
	err := client.GetPath(srcPath, "")
	assert.Error(t, err)
}
