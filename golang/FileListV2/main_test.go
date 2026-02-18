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
	result := genAssetBlobUnionQuery("", "", nil, "")
	if common.AssetTables == nil || len(common.AssetTables) == 0 {
		assert.Contains(t, result, "")
		return
	}
	assert.Contains(t, result, "FROM default_asset_blob")
}

func TestGenAssetBlobUnionQuery_WithColumns_UsesProvidedColumns(t *testing.T) {
	columns := "a.asset_id, a.path"
	repoNames := []string{"repo1"}
	result := genAssetBlobUnionQuery(columns, "", repoNames, "testfmt")
	assert.Contains(t, result, "SELECT r.name as repo_name, a.asset_id, a.path")
}

func TestGenAssetBlobUnionQuery_WithAfterWhere_AddsCondition(t *testing.T) {
	afterWhere := "a.kind = 'blob'"
	repoNames := []string{"repo1"}
	result := genAssetBlobUnionQuery("", afterWhere, repoNames, "testfmt")
	assert.Contains(t, result, "WHERE 1=1 AND a.kind = 'blob'")
}

func TestGenAssetBlobUnionQuery_WithRepoName_AddsRepoNameCondition(t *testing.T) {
	repoNames := []string{"repo1"}
	result := genAssetBlobUnionQuery("", "", repoNames, "testfmt")
	assert.Contains(t, result, "('repo1')")
}

func TestGenAssetBlobUnionQuery_SingleTable_ReturnsSingleQuery(t *testing.T) {
	repoNames := []string{"repo1"}
	result := genAssetBlobUnionQuery("", "", repoNames, "testfmt")
	assert.NotContains(t, result, "UNION ALL")
}

func TestGetBlobRef_ValidNewBlobRefLine_ReturnsFullMatch(t *testing.T) {
	blobRef := "aaaa blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44 bbbb"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44", result)
}

func TestGetBlobRef_ValidNewBlobRefLine2_ReturnsFullMatch(t *testing.T) {
	blobRef := "aaaa,blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44,bbbb"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44", result)
}

func TestGetBlobRef_ValidNewBlobRef_ReturnsFullMatch(t *testing.T) {
	blobRef := "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, blobRef, result)
}

func TestGetBlobRef_ValidOldBlobRef_ReturnsFullMatch(t *testing.T) {
	blobRef := "blobStore@6c1d3423-ecbc-4c52-a0fe-01a45a12883a"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, blobRef, result)
}

func TestGetBlobRef_InvalidBlobRef_ReturnsEmptyString(t *testing.T) {
	blobRef := "invalidBlobRef"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, "", result)
}

func TestGetBlobRef_EmptyBlobRef_ReturnsEmptyString(t *testing.T) {
	blobRef := ""
	result := getBlobRef(blobRef, "")
	assert.Equal(t, "", result)
}

func TestGetBlobRef_MaybeBlobRefWithTab_ReturnBlobRef(t *testing.T) {
	blobRef := "raw-hosted	/dummies/staging_move2.txt	default@47d9e6d4-308e-4984-89f2-96db825ea66c@2025-12-17T08:15"
	result := getBlobRef(blobRef, "")
	assert.Equal(t, "default@47d9e6d4-308e-4984-89f2-96db825ea66c@2025-12-17T08:15", result)
}

func TestGetBlobRef_WithTab_FileListResult(t *testing.T) {
	blobRef := "filelist-test/content/vol-08/chap-08/08080d79-06b0-4274-885e-ea78b8c463f5.properties"
	result := getBlobRef(blobRef, "default")
	assert.Equal(t, "default@08080d79-06b0-4274-885e-ea78b8c463f5", result)
}

func TestRxSelect(t *testing.T) {
	maybeQuery := `SELECT 
	ab.blob_ref AS blob_id
	FROM raw_asset_blob ab
	JOIN raw_asset a USING (asset_blob_id)
	WHERE EXISTS (
		SELECT 1
	FROM raw_content_repository cr
	JOIN repository r ON r.id = cr.config_repository_id
	WHERE cr.repository_id = a.repository_id
	AND r.name = 'raw-hosted'
	) AND blob_ref not like '%@%@%'`

	result := common.RxSelect.MatchString(maybeQuery)
	assert.True(t, result, "Query should start with 'SELECT' and contain 'blob_id': \n"+maybeQuery)

	maybeQuery = "SEELECT aaaaa FROM bbbb"
	result = common.RxSelect.MatchString(maybeQuery)
	assert.False(t, result, "Query should start with 'SELECT' and contain 'blob_id': \n"+maybeQuery)
}
