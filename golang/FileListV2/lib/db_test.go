package lib

import (
	"FileListV2/common"
	"testing"
)

func TestMain(m *testing.M) {
	common.Debug = true
	//m.Run()
}

func TestQuery_DBIsNil(t *testing.T) {
	rows := Query("SELECT * FROM repository", nil, 1000)
	if rows != nil {
		t.Error("Expected nil, got", rows)
	}

	rows = Query("SELECT * FROM repository", nil, 0)
	if rows != nil {
		t.Error("Expected nil, got", rows)
	}
}
