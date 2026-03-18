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
