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
}

func TestGetContentPath_S3_ReturnsPrifixPlusContent(t *testing.T) {
	common.BsType = "s3"
	// TODO: not sure if this is correct, but for now, returning relative path
	result := GetContentPath("s3://s3-test-bucket/s3-test-prefix/")
	assert.Equal(t, "content", result)
}

func TestOpenStdInOrFile_StdIn_ReturnsStdin(t *testing.T) {
	result := OpenStdInOrFIle("-")
	assert.Equal(t, os.Stdin, result)
}

func TestOpenStdInOrFile_InvalidFile_ReturnsNil(t *testing.T) {
	f, _ := os.CreateTemp("", "TestOpenStdInOrFile_InvalidFile_ReturnsNil-")
	result := OpenStdInOrFIle(f.Name())
	//t.Logf("%v", f.Name())
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

func TestGetContentPath_EmptyBsType_ReturnsFullPath(t *testing.T) {
	common.BsType = ""
	result := GetContentPath("/base/dir")
	assert.Equal(t, "/base/dir/content", result)
}

func TestGetContentPath_S3BsType_ReturnsContentOnly(t *testing.T) {
	common.BsType = "s3"
	result := GetContentPath("s3://s3-test-bucket/s3-test-prefix/")
	assert.Equal(t, "content", result)
}

func TestGetContentPath_FileBsType_ReturnsFullPath(t *testing.T) {
	common.BsType = "file"
	result := GetContentPath("/base/dir")
	assert.Equal(t, "/base/dir/content", result)
}

func TestGetContentPath_FileBsType_PathContainingContent(t *testing.T) {
	common.BsType = "file"
	result := GetContentPath("/base/dir/content/vol-NN/chap-MM")
	assert.Equal(t, "/base/dir/content", result)
}
func TestGetContentPath_UnknownBsType_ReturnsEmptyString(t *testing.T) {
	common.BsType = "unknown"
	result := GetContentPath("/base/dir")
	assert.Equal(t, "", result)
}

func TestGetUpToContent_PathWithContentSubdir_ReturnsUpToContent(t *testing.T) {
	result := GetUpToContent("sonatype-work/nexus3/blobs/default/content/vol-NN")
	assert.Equal(t, "sonatype-work/nexus3/blobs/default/content", result)
}

func TestGetUpToContent_PathEndingWithContent_ReturnsSamePath(t *testing.T) {
	result := GetUpToContent("sonatype-work/nexus3/blobs/default/content")
	assert.Equal(t, "sonatype-work/nexus3/blobs/default/content", result)
}

func TestGetUpToContent_PathWithoutContent_AddsContent(t *testing.T) {
	result := GetUpToContent("sonatype-work/nexus3/blobs/default")
	assert.Equal(t, "sonatype-work/nexus3/blobs/default/content", result)
}

func TestGetUpToContent_EmptyPath_ReturnsContent(t *testing.T) {
	result := GetUpToContent("")
	assert.Equal(t, "content", result)
}

func TestGetUpToContent_PathWithMultipleContentSubdirs_ReturnsLastContent(t *testing.T) {
	result := GetUpToContent("sonatype-work/nexus3/content/blobs/default/content/vol-NN")
	assert.Equal(t, "sonatype-work/nexus3/content/blobs/default/content", result)
}
