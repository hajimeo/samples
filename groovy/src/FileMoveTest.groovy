#!/usr/bin/env groovy
// BlobStoreMoveTest.groovy
// Replicates FileBlobStore.tryCreate: write large file to /content/tmp/, then move to final path.
// Run: groovy BlobStoreMoveTest.groovy {file_blobstore_path} {dummy_file_path}

import java.nio.file.*

def blobStoreRoot = args.length > 0 ? Path.of(args[0]) : null
if (!blobStoreRoot || !Files.exists(blobStoreRoot)) {
    println "Error: blob_store_root is required and must exist."
    System.exit(1)
}
def dummyFilePath = args.length > 1 ? Path.of(args[1]) : null
if (!dummyFilePath || !Files.exists(dummyFilePath)) {
    println "Error: dummy_file_path is required and must exist."
    System.exit(1)
}

def contentDir    = blobStoreRoot.resolve("content")
def tmpDir        = contentDir.resolve("tmp")
def blobId        = UUID.randomUUID().toString()
def uuid          = UUID.randomUUID().toString()

// Mirrors temporaryContentPath and contentPath in FileBlobStore (except using `tmp${blobId}.bytes`)
def tmpBlobPath   = tmpDir.resolve("${blobId}.${uuid}.bytes")
def finalDir      = contentDir.resolve("2026/06/19/00/00")
def finalBlobPath = finalDir.resolve("${blobId}.bytes")

Files.createDirectories(tmpDir)
Files.createDirectories(finalDir)

println "=== FileBlobStore move test ==="
println "Blob store root : ${blobStoreRoot}"
println "Source file     : ${dummyFilePath}"
println "Temp path       : ${tmpBlobPath}"
println "Final path      : ${finalBlobPath}"
println ""

// --- Phase 1: simulate ingester.ingestTo(temporaryBlobPath) ---
println "[1] Copying ${dummyFilePath} to temp path..."
def t0 = System.currentTimeMillis()
Files.copy(dummyFilePath, tmpBlobPath, StandardCopyOption.REPLACE_EXISTING)
def writeMs = System.currentTimeMillis() - t0
def fileSize = Files.size(tmpBlobPath)
def sha256 = java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(tmpBlobPath)).encodeHex().toString()
println "    Done in ${writeMs} ms (${String.format('%.1f', fileSize / 1024.0 / 1024.0 / (writeMs / 1000.0))} MB/s)"
println "    SHA-256: ${sha256}"
println ""

// --- Phase 2: simulate move(temporaryBlobPath, blobPath) ---
// FileBlobStore.move() tries ATOMIC_MOVE first, falls back to plain move
println "[2] Moving temp → final (ATOMIC_MOVE)..."
def t1 = System.currentTimeMillis()
try {
    Files.move(tmpBlobPath, finalBlobPath, StandardCopyOption.ATOMIC_MOVE)
    def moveMs = System.currentTimeMillis() - t1
    println "    ATOMIC_MOVE succeeded in ${moveMs} ms"
} catch (AtomicMoveNotSupportedException e) {
    println "    ATOMIC_MOVE not supported (${e.message}), falling back to plain move..."
    Files.move(tmpBlobPath, finalBlobPath)
    def moveMs = System.currentTimeMillis() - t1
    println "    Plain move done in ${moveMs} ms"
}
println ""

// --- Verify ---
def finalSize = Files.size(finalBlobPath)
def finalSha256 = java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(finalBlobPath)).encodeHex().toString()
println "Final file exists: ${Files.exists(finalBlobPath)}"
println "Final file size  : ${finalSize} bytes (expected ${Files.size(dummyFilePath)})"
println "Final file SHA-256: ${finalSha256} (expected ${sha256})"
println "Temp file gone   : ${!Files.exists(tmpBlobPath)}"

// Cleanup
Files.deleteIfExists(finalBlobPath)
println "Test completed and cleaned up ${finalBlobPath}."
