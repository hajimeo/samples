package main

import (
	"FileListV2/common"
	"github.com/stretchr/testify/assert"
	"os"
	"testing"
)

// TODO: this is not a right test as it seems os.Args is not working?
func TestSetGlobals_DefaultValues(t *testing.T) {
	os.Args = []string{"cmd"}
	setGlobals()
	assert.Equal(t, "./", common.BaseDir)
	assert.Equal(t, "", common.Filter4Path)
	assert.Equal(t, "", common.Filter4FileName)
	assert.Equal(t, "", common.Filter4PropsIncl)
	assert.Equal(t, "", common.Filter4PropsExcl)
	assert.Equal(t, "", common.SaveToFile)
	assert.Equal(t, "", common.Truth)
	assert.Equal(t, "", common.DbConnStr)
	assert.Equal(t, "", common.BlobIDFIle)
	assert.Equal(t, "", common.DelFromDateStr)
	assert.Equal(t, "", common.DelToDateStr)
	assert.Equal(t, "", common.ModFromDateStr)
	assert.Equal(t, "", common.ModToDateStr)
	assert.False(t, common.Debug)
	assert.False(t, common.Debug2)
}
