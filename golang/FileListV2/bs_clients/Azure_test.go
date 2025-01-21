package bs_clients

import (
	"FileListV2/common"
	"database/sql"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestAzClient(t *testing.T) {
	AzApi = &azblob.Client{}
	client := getAzApi()
	assert.Equal(t, AzApi, client)
}

func TestGetAzApi_ValidCredentials_ReturnsClient(t *testing.T) {
	accountName := h.GetEnv("AZURE_STORAGE_ACCOUNT_NAME", "")
	if accountName == "" {
		t.Skip("AZURE_STORAGE_ACCOUNT_NAME is not set")
		//os.Setenv("AZURE_STORAGE_ACCOUNT_NAME", "hajimeteststorage")
		//os.Setenv("AZURE_STORAGE_ACCOUNT_KEY", "************************")
	}
	accountName = h.GetEnv("AZURE_STORAGE_ACCOUNT_NAME", "")
	AzApi = nil
	client := getAzApi()

	assert.NotNil(t, client)
	//t.Logf("URL: %v", client.URL())
	assert.Contains(t, client.URL(), accountName+".blob.core.windows.net/")
}

func TestGetAzApi_AlreadyInitialized_ReturnsExistingClient(t *testing.T) {
	existingClient := &azblob.Client{}
	AzApi = existingClient

	client := getAzApi()

	assert.Equal(t, existingClient, client)
}

func TestReadPath_ValidPath_ReturnsContents_Azure(t *testing.T) {
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

	path := "metadata.properties"

	azClient := AzClient{}
	AzApi = nil
	contents, err := azClient.ReadPath(path)

	assert.NoError(t, err)
	assert.Contains(t, contents, "type=azure")
}

func TestReadPath_InvalidPath_ReturnsError_Azure(t *testing.T) {
	path := "invalid_path"

	azClient := AzClient{}
	contents, err := azClient.ReadPath(path)

	assert.Error(t, err)
	t.Logf("err: %s", err.Error())
	assert.Equal(t, "", contents)
}

func TestWriteToPath_ValidPath_WritesContents_Azure(t *testing.T) {
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

	path := "write_test.txt"
	contents := "file contents"

	azClient := AzClient{}
	err := azClient.WriteToPath(path, contents)

	assert.NoError(t, err)
}

func TestRemoveDeleted_ContainsDeletedLine_RemovesLine(t *testing.T) {
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

	path := "test_test.txt"
	contents := "line1\ndeleted=true\nline2"
	azClient := AzClient{}

	err := azClient.WriteToPath(path, contents)
	if err != nil {
		t.Skipf("WriteToPath failed with error: %s", err.Error())
	}

	err = azClient.RemoveDeleted(path, contents)
	assert.NoError(t, err)

	updatedContents, err2 := azClient.ReadPath(path)
	assert.NoError(t, err2)
	assert.Contains(t, updatedContents, "line1\n")
	assert.NotContains(t, updatedContents, "deleted=true")
}

func TestGetDirs_ValidBaseDir_ReturnsMatchingDirs(t *testing.T) {
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

	baseDir := "content"
	pathFilter := ""
	maxDepth := 5

	azClient := AzClient{}
	//h.DEBUG = true
	dirs, err := azClient.GetDirs(baseDir, pathFilter, maxDepth)

	assert.NoError(t, err)
	t.Logf("dirs: %v", dirs)
	assert.Greater(t, len(dirs), 1)
	assert.Contains(t, dirs[0], "content/vol-")
}

func TestGetDirs_EmptyBaseDir_ReturnsError_Azure(t *testing.T) {
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

	baseDir := ""
	pathFilter := ".*"
	maxDepth := 2

	azClient := AzClient{}
	dirs, err := azClient.GetDirs(baseDir, pathFilter, maxDepth)

	assert.Error(t, err)
	assert.Nil(t, dirs)
}

func TestGetDirs_InvalidPathFilter_ReturnsNoDirs(t *testing.T) {
	baseDir := "base_dir"
	pathFilter := "["
	maxDepth := 2

	azClient := AzClient{}
	dirs, err := azClient.GetDirs(baseDir, pathFilter, maxDepth)

	assert.NoError(t, err)
	assert.Empty(t, dirs)
}

func TestListObjects_Azure(t *testing.T) {
	accountName := h.GetEnv("AZURE_STORAGE_ACCOUNT_NAME", "")
	if accountName == "" {
		t.Skip("AZURE_STORAGE_ACCOUNT_NAME is not set")
	}
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	t.Logf("containerName: %v", containerName)
	common.Container = containerName

	h.DEBUG = true
	azClient := AzClient{}
	db := &sql.DB{}
	common.TopN = 1

	testFunc := func(args PrintLineArgs) bool {
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("DEBUG", fmt.Sprintf("testFunc found Printed %d >= %d", common.PrintedNum, common.TopN))
			return false
		}
		t.Logf("path: %v (%d)", args.Path.(string), common.PrintedNum)
		common.PrintedNum++
		return true
	}

	common.PrintedNum = 0
	subTtl := azClient.ListObjects("", db, testFunc)
	t.Logf("subTtl: %v", subTtl)
	assert.Greater(t, subTtl, int64(0))

	common.PrintedNum = 0
	subTtl = azClient.ListObjects("content", db, testFunc)
	t.Logf("subTtl under content: %v", subTtl)
	assert.Greater(t, subTtl, int64(0))
}
