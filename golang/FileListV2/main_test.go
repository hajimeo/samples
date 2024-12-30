package main

import (
	"FileListV2/common"
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

func TestGenAssetBlobUnionQuery_NoAssetTableNames_UsesDefaultAssetTables(t *testing.T) {
	result := genAssetBlobUnionQuery(nil, "", "", nil, "")
	if common.AssetTables == nil || len(common.AssetTables) == 0 {
		assert.Contains(t, result, "")
		return
	}
	assert.Contains(t, result, "FROM default_asset_blob")
}

func TestGenAssetBlobUnionQuery_WithAssetTableNames_UsesProvidedAssetTables(t *testing.T) {
	assetTableNames := []string{"table1", "table2"}
	result := genAssetBlobUnionQuery(assetTableNames, "", "", nil, "")
	assert.Contains(t, result, "FROM table1_blob")
	assert.Contains(t, result, "FROM table2_blob")
}

func TestGenAssetBlobUnionQuery_WithColumns_UsesProvidedColumns(t *testing.T) {
	columns := "a.asset_id, a.path"
	result := genAssetBlobUnionQuery([]string{"table1"}, columns, "", nil, "")
	assert.Contains(t, result, "SELECT a.asset_id, a.path")
}

func TestGenAssetBlobUnionQuery_WithAfterWhere_AddsCondition(t *testing.T) {
	afterWhere := "a.kind = 'blob'"
	result := genAssetBlobUnionQuery([]string{"table1"}, "", afterWhere, nil, "")
	assert.Contains(t, result, "WHERE 1=1 AND a.kind = 'blob'")
}

func TestGenAssetBlobUnionQuery_WithRepoName_AddsRepoNameCondition(t *testing.T) {
	repoNames := []string{"repo1"}
	result := genAssetBlobUnionQuery([]string{"table1"}, "", "", repoNames, "test")
	assert.Contains(t, result, "('repo1')")
}

func TestGenAssetBlobUnionQuery_SingleTable_ReturnsSingleQuery(t *testing.T) {
	result := genAssetBlobUnionQuery([]string{"table1"}, "", "", nil, "")
	assert.NotContains(t, result, "UNION ALL")
}

func TestGenAssetBlobUnionQuery_MultipleTables_ReturnsUnionQuery(t *testing.T) {
	result := genAssetBlobUnionQuery([]string{"table1", "table2"}, "", "", nil, "")
	assert.Contains(t, result, "UNION ALL")
}
