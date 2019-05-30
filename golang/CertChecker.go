/**
 * Simple certificate (PEM format) checker
 * ./CertChecker some_file.pem
 */
package main

import (
    "crypto/x509"
    "encoding/pem"
    "github.com/pkg/errors"
    "io/ioutil"
    "os"
    "fmt"
)

func check(e error, msg string) {
    if e != nil {
        wrappedErr := errors.Wrap(e, msg)
        fmt.Printf("%+v\n", wrappedErr)
        os.Exit(1)
    }
}

func main() {
    cert_file := os.Args[1]
    certRawData, err := ioutil.ReadFile(cert_file)
    check(err, "ReadFile")
    certData, _ := pem.Decode([]byte(certRawData))
    //certData, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(certRawData)))
    check(err, "Decode")
    //certParsed, err := x509.ParsePKIXPublicKey(certData.Bytes)
    certParsed, err := x509.ParseCertificate(certData.Bytes)
    check(err, "ParseCertificate")
    fmt.Printf("%+v\n", certParsed)
}
