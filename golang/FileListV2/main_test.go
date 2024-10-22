package main

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestExtractBlobId_ValidPath_ReturnsBlobId(t *testing.T) {
	path := "vol-01/chap-01/f062f002-88f0-4b53-aeca-7324e9609329.properties"
	result := extractBlobIdFromString(path)
	assert.Equal(t, "f062f002-88f0-4b53-aeca-7324e9609329", result)
}

func TestExtractBlobId_InvalidPath_ReturnsEmptyString(t *testing.T) {
	path := "invalid/path/noBlobId.txt"
	result := extractBlobIdFromString(path)
	assert.Equal(t, "", result)
}

func TestExtractBlobId_EmptyPath_ReturnsEmptyString(t *testing.T) {
	path := ""
	result := extractBlobIdFromString(path)
	assert.Equal(t, "", result)
}

func TestExtractBlobId_PathWithMultipleMatches_ReturnsFirstMatch(t *testing.T) {
	path := "vol-01/chap-01/f062f002-88f0-4b53-aeca-7324e9609329.properties/f062f002-88f0-4b53-aeca-7324e9609999.properties"
	result := extractBlobIdFromString(path)
	assert.Equal(t, "f062f002-88f0-4b53-aeca-7324e9609329", result)
}

func TestIsTsMSecBetweenTs_WithinRange_ReturnsTrue(t *testing.T) {
	result := isTsMSecBetweenTs(1609459200000, 1609455600, 1609462800)
	assert.True(t, result)
}

func TestIsTsMSecBetweenTs_BelowRange_ReturnsFalse(t *testing.T) {
	result := isTsMSecBetweenTs(1609452000000, 1609455600, 1609462800)
	assert.False(t, result)
}

func TestIsTsMSecBetweenTs_AboveRange_ReturnsFalse(t *testing.T) {
	result := isTsMSecBetweenTs(1609466400000, 1609455600, 1609462800)
	assert.False(t, result)
}

func TestIsTsMSecBetweenTs_ZeroFromTs_ReturnsTrue(t *testing.T) {
	result := isTsMSecBetweenTs(1609459200000, 0, 1609462800)
	assert.True(t, result)
}

func TestIsTsMSecBetweenTs_ZeroToTs_ReturnsTrue(t *testing.T) {
	result := isTsMSecBetweenTs(1609459200000, 1609455600, 0)
	assert.True(t, result)
}

func TestMyHashCode_EmptyString_ReturnsZero(t *testing.T) {
	result := myHashCode("")
	assert.Equal(t, int32(0), result)
}

func TestMyHashCode_NonEmptyString_ReturnsHash(t *testing.T) {
	result := myHashCode("test")
	assert.Equal(t, int32(3556498), result)
}

func TestGenBlobPath_ValidBlobId_ReturnsCorrectPath(t *testing.T) {
	result := genBlobPath("f062f002-88f0-4b53-aeca-7324e9609329", ".properties")
	expected := "vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties"
	assert.Equal(t, expected, result)
}

func TestGenBlobPath_EmptyBlobId_ReturnsCorrectPath(t *testing.T) {
	result := genBlobPath("", ".properties")
	expected := ""
	assert.Equal(t, expected, result)
}
