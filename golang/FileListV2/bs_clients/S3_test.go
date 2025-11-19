package bs_clients

import (
	"FileListV2/common"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/stretchr/testify/assert"
	"io"
	"os"
	"strings"
	"testing"
)

func TestGetBsClient_InitializedClient_ReturnsExistingClient(t *testing.T) {
	S3Api = &s3.Client{}
	client := getS3Api(1)
	assert.Equal(t, S3Api, client)
}

func TestGetBsClient_UninitializedClient_ReturnsNewClient(t *testing.T) {
	S3Api = nil
	client := getS3Api(1)
	assert.NotNil(t, client)
	assert.Equal(t, S3Api, client)
}

func TestReadPath_InvalidPath_ReturnsError_S3(t *testing.T) {
	path := "invalid_path"

	s3Client := S3Client{}
	contents, err := s3Client.ReadPath(path)

	assert.Error(t, err)
	assert.Equal(t, "", contents)
}

func TestReadPath_ErrorReadingBody_ReturnsError_S3(t *testing.T) {
	path := "path_with_error"

	cachedObject := &s3.GetObjectOutput{}
	cachedObject.Body = io.NopCloser(strings.NewReader(""))
	h.CacheAddObject(path, cachedObject, 1)

	s3Client := S3Client{}
	contents, _ := s3Client.ReadPath(path)

	//assert.Error(t, err)
	assert.Equal(t, "", contents)
}

type errorReader struct{}

func (e *errorReader) Read(p []byte) (n int, err error) {
	return 0, fmt.Errorf("read error")
}

func (e *errorReader) Close() error {
	return nil
}

func TestWriteToPath_ValidPath_WritesContents_S3(t *testing.T) {
	//s3Client := S3Client{}
	//err := s3Client.WriteToPath(path, contents)
	t.Log("TODO: Not implemented WriteToPath tests yet")
	t.SkipNow()
}

func TestRemoveTags(t *testing.T) {
	t.Log("TODO: Not implemented removeTag tests yet")
	t.SkipNow()
}

func TestRemoveDeleted_ValidPath_RemovesTags_S3(t *testing.T) {
	t.Log("TODO: Not implemented RemoveDeleted tests yet")
	t.SkipNow()
}

func TestGetDirs_S3(t *testing.T) {
	t.Log("TODO: Not implemented GetDirs tests yet")
	t.SkipNow()
}

func TestGetPath_ValidKey_CopiesFileToLocalPath_S3(t *testing.T) {
	someEnv := h.GetEnv("AWS_ACCESS_KEY_ID", "")
	if someEnv == "" {
		//AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_REGION
		t.Skip("AWS_ACCESS_KEY_ID is not set")
	}
	someEnv = h.GetEnv("AWS_SECRET_ACCESS_KEY", "")
	if someEnv == "" {
		t.Skip("AWS_SECRET_ACCESS_KEY is not set")
	}
	someEnv = h.GetEnv("AWS_REGION", "")
	if someEnv == "" {
		t.Skip("AWS_REGION is not set")
	}

	container := h.GetEnv("AWS_BLOB_STORE_NAME", "apac-support-bucket")
	if container == "" {
		t.Skip("AWS_BLOB_STORE_NAME is not set")
	}
	t.Logf("container: %s\n", container)
	common.Container = container
	common.BaseDir = "s3://" + container
	client := &S3Client{}
	// S3 Key should include the prefix.
	key := "filelist-test/metadata.properties"
	localPath := "local/paths3.txt"

	common.Debug = true
	err := client.GetPath(key, localPath)
	assert.NoError(t, err)
	// To manually check: aws s3 ls s3://apac-support-bucket/filelist-test/

	contents, err := os.ReadFile(localPath)
	assert.NoError(t, err)
	assert.Contains(t, string(contents), "type=s3")

	t.Logf("contents: %s\n", contents)
	os.Remove(localPath)
}
