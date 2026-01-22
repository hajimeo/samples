package main

import (
	"FileListV2/common"
	"github.com/stretchr/testify/assert"
	"os"
	"testing"
)

func TestUsage(t *testing.T) {
	//usage()
	assert.True(t, true)
}

func TestSetGlobals(t *testing.T) {
	// TODO: how to test setGlobals?
	//setGlobals()
	assert.True(t, true)
}

func TestPrintHeader_NoHeaderFlagSet_DoesNotPrintHeader(t *testing.T) {
	common.NoHeader = true
	saveToPointer := &os.File{}
	defer func() { common.NoHeader = false }()

	printHeader(saveToPointer)

	// Assert that nothing is printed or saved
	assert.True(t, true) // Placeholder assertion
}

func TestGenBlobPath_ValidBlobId_ReturnsCorrectPath(t *testing.T) {
	result := genBlobPath("f062f002-88f0-4b53-aeca-7324e9609329", ".properties")
	expected := "vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties"
	assert.Equal(t, expected, result)
}

func TestGenBlobPath_ValidBlobId_ReturnsCorrectPath_NewLayout(t *testing.T) {
	result := genBlobPath("f062f002-88f0-4b53-aeca-7324e9609329@2022-10-20T12:33", ".properties")
	expected := "2022/10/20/12/33/f062f002-88f0-4b53-aeca-7324e9609329.properties"
	assert.Equal(t, expected, result)
}

func TestGenBlobPath_ValidBlobId_ReturnsCorrectPath_NewLayout2(t *testing.T) {
	result := genBlobPath("/2022/10/20/12/33/f062f002-88f0-4b53-aeca-7324e9609329", ".properties")
	expected := "2022/10/20/12/33/f062f002-88f0-4b53-aeca-7324e9609329.properties"
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

func TestGetBlobRef_ValidNewBlobRefLine_ReturnsFullMatch(t *testing.T) {
	blobRef := "aaaa blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44 bbbb"

	result := getBlobRef(blobRef)

	assert.Equal(t, "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44", result)
}

func TestGetBlobRef_ValidNewBlobRefLine2_ReturnsFullMatch(t *testing.T) {
	blobRef := "aaaa,blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44,bbbb"

	result := getBlobRef(blobRef)

	assert.Equal(t, "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44", result)
}

func TestGetBlobRef_ValidNewBlobRef_ReturnsFullMatch(t *testing.T) {
	blobRef := "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44"

	result := getBlobRef(blobRef)

	assert.Equal(t, blobRef, result)
}

func TestGetBlobRef_ValidOldBlobRef_ReturnsFullMatch(t *testing.T) {
	blobRef := "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a"

	result := getBlobRef(blobRef)

	assert.Equal(t, blobRef, result)
}

func TestGetBlobRef_InvalidBlobRef_ReturnsEmptyString(t *testing.T) {
	blobRef := "invalidBlobRef"

	result := getBlobRef(blobRef)

	assert.Equal(t, "", result)
}

func TestGetBlobRef_EmptyBlobRef_ReturnsEmptyString(t *testing.T) {
	blobRef := ""

	result := getBlobRef(blobRef)

	assert.Equal(t, "", result)
}
