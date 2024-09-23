package lib

import (
	"FileListV2/common"
	"github.com/stretchr/testify/assert"
	"os"
	"testing"
)

func TestGetSchema_ValidURL_ReturnsSchema(t *testing.T) {
	result := GetSchema("https://example.com")
	assert.Equal(t, "https", result)
	result = GetSchema("./sonatype-work/nexus3/blobs/default/content")
	assert.Equal(t, "", result)
	result = GetSchema("file://sonatype-work/nexus3/blobs/default/content")
	assert.Equal(t, "file", result)
	result = GetSchema("s3://s3-test-bucket/s3-test-prefix/")
	assert.Equal(t, "s3", result)
	result = GetSchema("://invalid-url")
	assert.Equal(t, "", result)
}

func TestGetContentPath_NoType_ReturnsFullPath(t *testing.T) {
	common.BsType = ""
	result := GetContentPath("/base/dir")
	assert.Equal(t, "/base/dir/content", result)
	common.BsType = "s3"
	result = GetContentPath("s3://s3-test-bucket/s3-test-prefix/")
	assert.Equal(t, "/content", result)
}

func TestOpenStdInOrFile_StdIn_ReturnsStdin(t *testing.T) {
	result := OpenStdInOrFIle("-")
	assert.Equal(t, os.Stdin, result)
}

func TestOpenStdInOrFile_InvalidFile_ReturnsNil(t *testing.T) {
	result := OpenStdInOrFIle("testdata/sample.txt")
	assert.NotNil(t, result)
}

func TestSortToSingleLine_ValidContent_ReturnsSortedSingleLine(t *testing.T) {
	result := SortToSingleLine("b\nc\na")
	assert.Equal(t, "a,b,c", result)
}

func TestSortToSingleLine_EmptyContent_ReturnsEmptyString(t *testing.T) {
	result := SortToSingleLine("")
	assert.Equal(t, "", result)
}
