package lib

import (
	"FileListV2/common"
	"github.com/stretchr/testify/assert"
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

func TestGetContentPath_S3_ReturnsPrefixPlusContent(t *testing.T) {
	common.BsType = "s3"
	common.Container = "s3-test-bucket"
	// TODO: not sure if this is correct, but for now, returning relative path
	result := GetContentPath("s3://s3-test-bucket/s3-test-prefix/")
	assert.Equal(t, "s3-test-prefix/content", result)
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
	result := GetContentPath("/base/dir")
	assert.Equal(t, "/base/dir/content", result)
}

func TestGetContentPath_FileBsType_ReturnsFullPath(t *testing.T) {
	result := GetContentPath("/base/dir")
	assert.Equal(t, "/base/dir/content", result)
}

func TestGetContentPath_FileBsType_PathContainingContent(t *testing.T) {
	result := GetContentPath("/base/dir/content/vol-NN/chap-MM")
	assert.Equal(t, "/base/dir/content", result)
}

func TestGetContentPath_WithProtocol_PathContainingContent(t *testing.T) {
	result := GetContentPath("file://base/dir/content/vol-NN/chap-MM")
	assert.Equal(t, "base/dir/content", result)
}

func TestGetContentPath_WithProtocol_FullPathContainingContent(t *testing.T) {
	result := GetContentPath("file:///tmp/base/dir/content/vol-NN/chap-MM")
	assert.Equal(t, "/tmp/base/dir/content", result)
}

func TestGetContentPath_WithProtocol_FullPathContainingContent2(t *testing.T) {
	result := GetContentPath("file:///Users/hosako/Documents/tests/nxrm_3.73.0-12_nxrm3730/sonatype-work/nexus3/blobs/default/")
	assert.Equal(t, "/Users/hosako/Documents/tests/nxrm_3.73.0-12_nxrm3730/sonatype-work/nexus3/blobs/default/content", result)
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
func TestIsTsMSecBetweenTs_WithinRange_ReturnsTrue(t *testing.T) {
	result := IsTsMSecBetweenTs(1609459200000, 1609455600, 1609462800)
	assert.True(t, result)
}

func TestIsTsMSecBetweenTs_BelowRange_ReturnsFalse(t *testing.T) {
	result := IsTsMSecBetweenTs(1609452000000, 1609455600, 1609462800)
	assert.False(t, result)
}

func TestIsTsMSecBetweenTs_AboveRange_ReturnsFalse(t *testing.T) {
	result := IsTsMSecBetweenTs(1609466400000, 1609455600, 1609462800)
	assert.False(t, result)
}

func TestIsTsMSecBetweenTs_ZeroFromTs_ReturnsTrue(t *testing.T) {
	result := IsTsMSecBetweenTs(1609459200000, 0, 1609462800)
	assert.True(t, result)
}

func TestIsTsMSecBetweenTs_ZeroToTs_ReturnsTrue(t *testing.T) {
	result := IsTsMSecBetweenTs(1609459200000, 1609455600, 0)
	assert.True(t, result)
}

func TestMyHashCode_EmptyString_ReturnsZero(t *testing.T) {
	result := HashCode("")
	assert.Equal(t, int32(0), result)
}

func TestMyHashCode_NonEmptyString_ReturnsHash(t *testing.T) {
	result := HashCode("test")
	assert.Equal(t, int32(3556498), result)
}

func TestGetContainerAndPrefix_ValidURL_ReturnsHostnameAndPrefix(t *testing.T) {
	hostname, prefix := GetContainerAndPrefix("https://example.com/path/to/content")
	assert.Equal(t, "example.com", hostname)
	assert.Equal(t, "path/to", prefix) // not starting with /
	hostname, prefix = GetContainerAndPrefix("s3://s3-test-bucket/s3-test-prefix/content")
	assert.Equal(t, "s3-test-bucket", hostname)
	assert.Equal(t, "s3-test-prefix", prefix)
}

func TestGetContainerAndPrefix_InvalidURL_ReturnsEmptyStrings(t *testing.T) {
	hostname, prefix := GetContainerAndPrefix("://invalid-url")
	assert.Equal(t, "", hostname)
	assert.Equal(t, "", prefix)
}

func TestGetContainerAndPrefix_EmptyURL_ReturnsEmptyStrings(t *testing.T) {
	hostname, prefix := GetContainerAndPrefix("")
	assert.Equal(t, "", hostname)
	assert.Equal(t, "", prefix)
}

func TestGetContainerAndPrefix_URLWithoutPath_ReturnsHostnameAndEmptyPrefix(t *testing.T) {
	hostname, prefix := GetContainerAndPrefix("https://example.com")
	assert.Equal(t, "example.com", hostname)
	assert.Equal(t, "", prefix)
}

func TestGetContainerAndPrefix_URLWithContentPath_ReturnsHostnameAndTrimmedPrefix(t *testing.T) {
	hostname, prefix := GetContainerAndPrefix("https://example.com/path/to/content/vol-NN")
	assert.Equal(t, "example.com", hostname)
	assert.Equal(t, "path/to", prefix) // not starting with /
}

func TestPathWithoutExt_ValidPath_ReturnsPathWithoutExtension(t *testing.T) {
	result := GetPathWithoutExt("/path/to/file.txt")
	assert.Equal(t, "/path/to/file", result)
}

func TestPathWithoutExt_PathWithoutExtension_ReturnsSamePath(t *testing.T) {
	result := GetPathWithoutExt("/path/to/file")
	assert.Equal(t, "/path/to/file", result)
}

func TestPathWithoutExt_EmptyPath_ReturnsEmptyString(t *testing.T) {
	result := GetPathWithoutExt("")
	assert.Equal(t, "", result)
}

func TestPathWithoutExt_PathWithMultipleDots_RemovesOnlyLastExtension(t *testing.T) {
	result := GetPathWithoutExt("/path/to/file.tar.gz")
	assert.Equal(t, "/path/to/file.tar", result)
}

func TestPathWithoutExt_PathWithTrailingDot_RemovesTrailingDot(t *testing.T) {
	result := GetPathWithoutExt("/path/to/file.")
	assert.Equal(t, "/path/to/file", result)
}

func TestGetAfterContent_PathWithContentSubdir_ReturnsSubsequentPath(t *testing.T) {
	result := GetAfterContent("sonatype-work/nexus3/blobs/default/content/vol-NN/chap-MM/UUID.properties")
	assert.Equal(t, "vol-NN/chap-MM/UUID.properties", result)
}

func TestGetAfterContent_PathEndingWithContent_ReturnsEmptyString(t *testing.T) {
	result := GetAfterContent("sonatype-work/nexus3/blobs/default/content")
	assert.Equal(t, "", result)
}

func TestGetAfterContent_PathWithoutContent_ReturnsEmptyString(t *testing.T) {
	result := GetAfterContent("sonatype-work/nexus3/blobs/default")
	assert.Equal(t, "", result)
}

func TestGetAfterContent_EmptyPath_ReturnsEmptyString(t *testing.T) {
	result := GetAfterContent("")
	assert.Equal(t, "", result)
}

func TestGetAfterContent_PathWithMultipleContentSubdirs_ReturnsLastSubsequentPath(t *testing.T) {
	result := GetAfterContent("sonatype-work/nexus3/content/blobs/default/content/vol-NN")
	assert.Equal(t, "vol-NN", result)
}
