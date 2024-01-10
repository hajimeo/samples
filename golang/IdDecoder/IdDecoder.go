package main

import (
	"crypto/cipher"
	"crypto/des"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"golang.org/x/crypto/pbkdf2"
	"strings"
)

func hexDecode(hexStr string) []byte {
	decoded, err := hex.DecodeString(hexStr)
	if err != nil {
		panic(err)
	}
	return decoded
}

func getObfRid(b64string string) string {
	decoded, _ := base64.StdEncoding.DecodeString(b64string)
	ds := strings.Split(string(decoded), ":")
	return ds[1]
}

func bytesToShort(b []byte, offset int) uint16 {
	return binary.BigEndian.Uint16(b[offset : offset+2])
}

func bytesToLong(b []byte, offset int) uint64 {
	return binary.BigEndian.Uint64(b[offset : offset+8])
}

func main() {
	b64string := "Zm52Ml9wcml2YXRlX3JlbGVhc2VfcmVwb3NpdG9yeTphZGYxODQ0MmJhNDk4M2YwOTA2YWM4MDk4OGViNDliNg"

	password := "changeme"
	salt := "changeme"
	iv := "0123456789ABCDEF"

	key := pbkdf2.Key([]byte(password), []byte(salt), 1024, 64, sha1.New)
	block, err := des.NewCipher(key)
	if err != nil {
		panic(err)
	}

	mode := cipher.NewCBCDecrypter(block, hexDecode(iv))

	encrypted := getObfRid(b64string)
	decrypted := make([]byte, len(encrypted))
	mode.CryptBlocks(decrypted, []byte(encrypted))

	clusterId := bytesToShort(decrypted, 0)
	clusterPos := bytesToLong(decrypted, 2)

	fmt.Printf("#%d:%d\n", clusterId, clusterPos)
}
