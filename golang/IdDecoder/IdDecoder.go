package main

import (
	"crypto/cipher"
	"crypto/des"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"golang.org/x/crypto/pbkdf2"
	"strings"
)

func bytesToShort(b []byte, offset int) int16 {
	return int16(b[offset])<<8 | int16(b[offset+1])
}

func bytesToLong(b []byte, offset int) int64 {
	return int64(b[offset+7]) | int64(b[offset+6])<<8 | int64(b[offset+5])<<16 |
		int64(b[offset+4])<<24 | int64(b[offset+3])<<32 | int64(b[offset+2])<<40 |
		int64(b[offset+1])<<48 | int64(b[offset])<<56
}

func base64DecodeStripped(s string) (string, error) {
	if i := len(s) % 4; i != 0 {
		s += strings.Repeat("=", 4-i)
	}
	decoded, err := base64.StdEncoding.DecodeString(s)
	return string(decoded), err
}

func main() {
	b64string := "Zm52Ml9wcml2YXRlX3JlbGVhc2VfcmVwb3NpdG9yeTphZGYxODQ0MmJhNDk4M2YwMTViYmU5N2U3ZTQ3M2UxNg"
	password := "changeme"
	salt := "changeme"
	iv := "0123456789ABCDEF"

	// Decode base64 string
	encrypted, err := base64DecodeStripped(b64string)
	if err != nil {
		panic(err)
	}
	fmt.Printf("    encrypted = %s\n", encrypted)

	// Derive key from password using PBKDF2
	key := pbkdf2.Key([]byte(password), []byte(salt), 1024, 8, sha1.New)

	// Create DES cipher
	block, err := des.NewCipher(key)
	if err != nil {
		panic(err)
	}
	decoded, err := hex.DecodeString(strings.ToLower(iv))
	if err != nil {
		panic(err)
	}
	fmt.Printf("    (hex) decoded = %v %s\n", decoded, string(decoded))

	mode := cipher.NewCBCDecrypter(block, decoded)

	// Decrypt data
	decrypted := make([]byte, len(encrypted))
	mode.CryptBlocks(decrypted, []byte(encrypted))

	// Extract cluster ID and position
	clusterId := bytesToShort(decrypted, 0)
	clusterPos := bytesToLong(decrypted, 2)

	fmt.Printf("#%d:%d\n", clusterId, clusterPos)
}
