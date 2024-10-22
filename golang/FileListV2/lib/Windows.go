//go:build windows
// +build windows

package lib

import (
	"os"
)

func GetXid(info os.FileInfo) (string, string) {
	// TODO: not implemented yet
	return "", ""
}
