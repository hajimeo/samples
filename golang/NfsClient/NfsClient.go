package main

import (
	"log"
	"os"
	"strings"

	"github.com/hajimeo/samples/golang/helpers"
	"github.com/vmware/go-nfs-client/nfs"
	"github.com/vmware/go-nfs-client/nfs/rpc"
	"github.com/vmware/go-nfs-client/nfs/util"
)

var _DEBUG = helpers.GetBoolEnv("_DEBUG", false)

// https://github.com/vmware/go-nfs-client/blob/master/nfs/example/test/main.go
func main() {
	util.DefaultLogger.SetDebug(_DEBUG)
	if len(os.Args) < 3 {
		util.Infof("%s <host>:<target path> <directory to be created>", os.Args[0])
		os.Exit(-1)
	}

	b := strings.Split(os.Args[1], ":")

	host := b[0]
	target := b[1]
	dir := os.Args[2]

	util.Infof("host=%s target=%s dir=%s\n", host, target, dir)

	mount, err := nfs.DialMount(host)
	if err != nil {
		log.Fatalf("unable to dial MOUNT service: %v", err)
	}
	defer mount.Close()

	name, err := os.Hostname()
	if err != nil {
		log.Fatalf("unable to get the hostname of this machine: %v", err)
	}
	auth := rpc.NewAuthUnix(name, uint32(os.Getuid()), uint32(os.Getgid()))

	v, err := mount.Mount(target, auth.Auth())
	if err != nil {
		log.Fatalf("unable to mount volume: %v", err)
	}
	defer v.Close()

	// discover any system files such as lost+found or .snapshot
	dirs, err := ls(v, ".")
	if err != nil {
		log.Fatalf("ls: %s", err.Error())
	}
	baseDirCount := len(dirs)

	if _, err = v.Mkdir(dir, 0775); err != nil {
		log.Fatalf("mkdir error: %v", err)
	}

	if _, err = v.Mkdir(dir, 0775); err == nil {
		log.Fatalf("mkdir expected error")
	}

	// make a nested dir
	if _, err = v.Mkdir(dir+"/a", 0775); err != nil {
		log.Fatalf("mkdir error: %v", err)
	}

	// make a nested dir
	if _, err = v.Mkdir(dir+"/a/b", 0775); err != nil {
		log.Fatalf("mkdir error: %v", err)
	}

	dirs, err = ls(v, ".")
	if err != nil {
		log.Fatalf("ls: %s", err.Error())
	}

	// check the length.  There should only be 1 entry in the target (aside from . and .., et al)
	if len(dirs) != 1+baseDirCount {
		log.Fatalf("expected %d dirs, got %d", 1+baseDirCount, len(dirs))
	}

	// 10 MB file
	if err = testFileRW(v, "10mb", 10*1024*1024); err != nil {
		log.Fatalf("fail")
	}

	// 7b file
	if err = testFileRW(v, "7b", 7); err != nil {
		log.Fatalf("fail")
	}

	// should return an error
	if err = v.RemoveAll("7b"); err == nil {
		log.Fatalf("expected a NOTADIR error")
	} else {
		nfserr := err.(*nfs.Error)
		if nfserr.ErrorNum != nfs.NFS3ErrNotDir {
			log.Fatalf("Wrong error")
		}
	}

	if err = v.Remove("7b"); err != nil {
		log.Fatalf("rm(7b) err: %s", err.Error())
	}

	if err = v.Remove("10mb"); err != nil {
		log.Fatalf("rm(10mb) err: %s", err.Error())
	}

	_, _, err = v.Lookup(dir)
	if err != nil {
		log.Fatalf("lookup error: %s", err.Error())
	}

	if _, err = ls(v, "."); err != nil {
		log.Fatalf("ls: %s", err.Error())
	}

	if err = v.RmDir(dir); err == nil {
		log.Fatalf("expected not empty error")
	}

	for _, fname := range []string{"/one", "/two", "/a/one", "/a/two", "/a/b/one", "/a/b/two"} {
		if err = testFileRW(v, dir+fname, 10); err != nil {
			log.Fatalf("fail")
		}
	}

	if err = v.RemoveAll(dir); err != nil {
		log.Fatalf("error removing files: %s", err.Error())
	}

	outDirs, err := ls(v, ".")
	if err != nil {
		log.Fatalf("ls: %s", err.Error())
	}

	if len(outDirs) != baseDirCount {
		log.Fatalf("directory should be empty of our created files!")
	}

	if err = mount.Unmount(); err != nil {
		log.Fatalf("unable to umount target: %v", err)
	}

	mount.Close()
	util.Infof("Completed tests")
}
