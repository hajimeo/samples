package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"bytes"
	"context"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	h "github.com/hajimeo/samples/golang/helpers"
	"strings"
	"time"
)

type AzClient struct{}

var AzApi *azblob.Client

func getAzApi() *azblob.Client {
	if AzApi != nil {
		return AzApi
	}

	// TODO: https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/azidentity#readme-environment-variables
	accountName := h.GetEnv("AZURE_STORAGE_ACCOUNT_NAME", "")
	accountKey := h.GetEnv("AZURE_STORAGE_ACCOUNT_KEY", "")
	if accountName == "" || accountKey == "" {
		panic("Missing AZURE_STORAGE_ACCOUNT_NAME or AZURE_STORAGE_ACCOUNT_KEY")
	}
	var err error
	AzApi, err = azblob.NewClientFromConnectionString("DefaultEndpointsProtocol=https;AccountName="+accountName+";AccountKey="+accountKey+";EndpointSuffix=core.windows.net", nil)
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	return AzApi
}

func getAzObject(path string) (azblob.DownloadStreamResponse, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		return azblob.DownloadStreamResponse{}, fmt.Errorf("Container is not set")
	}
	ctx := context.Background()
	return getAzApi().DownloadStream(ctx, common.Container, path, nil)
}

func (a AzClient) ReadPath(path string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+path, int64(0))
	} else {
		// As S3, using *2
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for path:"+path, common.SlowMS*2)
	}

	resp, err := getAzObject(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getS3Object for %s failed with %s.", path, err.Error()))
		return "", err
	}
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("ReadFrom for %s failed with %s.", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(buf.String())
	return contents, nil
}
