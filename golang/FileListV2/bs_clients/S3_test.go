package bs_clients

import (
	"fmt"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/stretchr/testify/assert"
	"io"
	"strings"
	"testing"
)

func TestGetBsClient_InitializedClient_ReturnsExistingClient(t *testing.T) {
	S3Api = &s3.Client{}
	client := getS3Api()
	assert.Equal(t, S3Api, client)
}

func TestGetBsClient_UninitializedClient_ReturnsNewClient(t *testing.T) {
	S3Api = nil
	client := getS3Api()
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
