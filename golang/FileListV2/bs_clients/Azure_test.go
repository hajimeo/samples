package bs_clients

import (
	"FileListV2/common"
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
	path := "metadata.properties"
	containerName := h.GetEnv("AZURE_STORAGE_CONTAINER_NAME", "")
	if containerName == "" {
		t.Skip("AZURE_STORAGE_CONTAINER_NAME is not set")
	}
	common.Container = containerName

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
