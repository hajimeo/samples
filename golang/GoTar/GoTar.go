/*
*
TODO: not implemented yet but just copied an example

This is for workaround-ing "kubectl cp":
error: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "3c3a55ca96e0bef988a53ed7a513461a81b013b2ba99aba3bb02986c13fe687f": OCI runtime exec failed: exec failed: container_linux.go:370: starting container process caused: exec: "tar": executable file not found in $PATH: unknown

https://github.com/kubernetes/kubernetes/blob/c98bde46c51ab854099b9fb06a2041fdfb9bf40b/staging/src/k8s.io/kubectl/pkg/cmd/cp/cp.go#L374

	Command:  []string{"tar", "cf", "-", t.src.File.String()},

https://github.com/kubernetes/kubernetes/blob/c98bde46c51ab854099b9fb06a2041fdfb9bf40b/staging/src/k8s.io/kubectl/pkg/cmd/cp/cp.go#L309

	cmdArr = []string{"tar", "-xmf", "-"}
	cmdArr = append(cmdArr, "-C", destFileDir)
*/
package main

import (
	"archive/tar"
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
)

func main() {
	// Create and add some files to the archive.
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	var files = []struct {
		Name, Body string
	}{
		{"readme.txt", "This archive contains some text files."},
		{"gopher.txt", "Gopher names:\nGeorge\nGeoffrey\nGonzo"},
		{"todo.txt", "Get animal handling license."},
	}
	for _, file := range files {
		hdr := &tar.Header{
			Name: file.Name,
			Mode: 0600,
			Size: int64(len(file.Body)),
		}
		if err := tw.WriteHeader(hdr); err != nil {
			log.Fatal(err)
		}
		if _, err := tw.Write([]byte(file.Body)); err != nil {
			log.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		log.Fatal(err)
	}

	// Open and iterate through the files in the archive.
	tr := tar.NewReader(&buf)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break // End of archive
		}
		if err != nil {
			log.Fatal(err)
		}
		fmt.Printf("Contents of %s:\n", hdr.Name)
		if _, err := io.Copy(os.Stdout, tr); err != nil {
			log.Fatal(err)
		}
		fmt.Println()
	}
}
