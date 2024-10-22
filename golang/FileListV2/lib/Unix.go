//go:build linux || darwin
// +build linux darwin

package lib

import (
	"os"
	"strconv"
	"syscall"
)

func GetXid(info os.FileInfo) (string, string) {
	stat := info.Sys().(*syscall.Stat_t)
	return strconv.Itoa(int(stat.Uid)), strconv.Itoa(int(stat.Gid))
}
