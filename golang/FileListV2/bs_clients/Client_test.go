package bs_clients

import (
	"github.com/stretchr/testify/assert"
	"os"
	"path/filepath"
	"testing"
)

func TestGetClient_ValidTypeAz_ReturnsAzClient(t *testing.T) {
	client := GetClient("az")
	assert.IsType(t, &AzClient{}, client)
}

func TestGetClient_ValidTypeFile_ReturnsFileClient(t *testing.T) {
	client := GetClient("file")
	assert.IsType(t, &FileClient{}, client)
}

func TestGetClient_EmptyType_ReturnsFileClient(t *testing.T) {
	client := GetClient("")
	assert.IsType(t, &FileClient{}, client)
}

func TestGetClient_UnsupportedTypePanics(t *testing.T) {
	assert.PanicsWithValue(t, "gs is currently not supported yet", func() {
		GetClient("gs")
	})
}

func TestGetClient_UnknownTypePanics(t *testing.T) {
	assert.PanicsWithValue(t, "Unknown type: unknown.", func() {
		GetClient("unknown")
	})
}

func TestCreateLocalFile_EmptyPath_ReturnsError(t *testing.T) {
	_, err := CreateLocalFile("")
	assert.NotNil(t, err)
	assert.EqualError(t, err, "localPath is not provided")
}

func TestCreateLocalFile_PathAlreadyExists_ReturnsError(t *testing.T) {
	existingFile := "/tmp/testdata/existing_file.txt"
	_ = os.MkdirAll(filepath.Dir(existingFile), os.ModePerm)
	_, _ = os.Create(existingFile)
	defer os.Remove(existingFile)

	_, err := CreateLocalFile(existingFile)
	assert.NotNil(t, err)
	assert.Contains(t, err.Error(), "already exists")
}

func TestCreateLocalFile_ValidPath_CreatesFile(t *testing.T) {
	validPath := "/tmp/testdata/new_file.txt"
	defer os.Remove(validPath)

	file, err := CreateLocalFile(validPath)
	assert.Nil(t, err)
	assert.NotNil(t, file)
	defer file.Close()

	_, statErr := os.Stat(validPath)
	assert.Nil(t, statErr)
}
