/**
 * Simple certificate (PEM format) checker
 * ./CertChecker some_file.pem
 */
package main

import (
    "crypto/x509"
    "encoding/pem"
    "io/ioutil"
    "os"
    "fmt"
)

func check(e error) {
    if e != nil {
        panic(e)
    }
}

func main() {
    cert_file := os.Args[1]
    certRawData, err := ioutil.ReadFile(cert_file)
    check(err)
    certData, _ := pem.Decode([]byte(certRawData))
    //certData, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(certRawData)))
    check(err)
    //certParsed, err := x509.ParsePKIXPublicKey(certData.Bytes)
    certParsed, err := x509.ParseCertificate(certData.Bytes)
    check(err)
    fmt.Printf("%+v\n", certParsed)
}
