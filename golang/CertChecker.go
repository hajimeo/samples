/**
 * Simple certificate (PEM format) checker
 * ./CertChecker some_file.pem
 */
package main

import (
    "crypto/x509"
    "crypto/x509/pkix"
    "encoding/asn1"
    "encoding/pem"
    "github.com/pkg/errors"
    "io/ioutil"
    "math/big"
    "os"
    "fmt"
    "time"
)

func check(e error, msg string) {
    if e != nil {
        wrappedErr := errors.Wrap(e, msg)
        fmt.Printf("%+v\n", wrappedErr)
        os.Exit(1)
    }
}

type certificate struct {
    Raw                asn1.RawContent
    TBSCertificate     tbsCertificate
    SignatureAlgorithm pkix.AlgorithmIdentifier
    SignatureValue     asn1.BitString
}
type tbsCertificate struct {
    Raw                asn1.RawContent
    Version            int `asn1:"optional,explicit,default:0,tag:0"`
    SerialNumber       *big.Int
    SignatureAlgorithm pkix.AlgorithmIdentifier
    Issuer             asn1.RawValue
    Validity           validity
    Subject            asn1.RawValue
    PublicKey          publicKeyInfo
    UniqueId           asn1.BitString   `asn1:"optional,tag:1"`
    SubjectUniqueId    asn1.BitString   `asn1:"optional,tag:2"`
    Extensions         []pkix.Extension `asn1:"optional,explicit,tag:3"`
}
type validity struct {
    NotBefore, NotAfter time.Time
}
type publicKeyInfo struct {
    Raw       asn1.RawContent
    Algorithm pkix.AlgorithmIdentifier
    PublicKey asn1.BitString
}

func ParseCertificate(asn1Data []byte) (*x509.Certificate, error) {
    var cert certificate
    rest, err := asn1.Unmarshal(asn1Data, &cert)
    if err != nil {
        return nil, err
    }
    if len(rest) > 0 {
        return nil, asn1.SyntaxError{Msg: "trailing data"}
    }
    return nil, err
}

func main() {
    cert_file := os.Args[1]
    certRawData, err := ioutil.ReadFile(cert_file)
    check(err, "ReadFile")
    certData, _ := pem.Decode([]byte(certRawData))
    //certData, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(certRawData)))
    check(err, "Decode")
    //certParsed, err := x509.ParsePKIXPublicKey(certData.Bytes)
    certParsed, err := ParseCertificate(certData.Bytes)
    check(err, "ParseCertificate")
    fmt.Printf("%+v\n", certParsed)
}
