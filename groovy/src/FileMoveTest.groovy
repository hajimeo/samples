#!/usr/bin/env groovy
// BlobStoreMoveTest.groovy
// Replicates FileBlobStore.tryCreate: write large file to /content/tmp/, then move to final path.
// Run: groovy BlobStoreMoveTest.groovy {file_blobstore_path} {dummy_file_path}

import java.nio.file.*
import java.nio.file.attribute.BasicFileAttributes

def blobStoreRoot = args.length > 0 ? Path.of(args[0]) : Path.of("/tmp/blobstore-test")
def fileSizeMB    = args.length > 1 ? args[1].toLong() : 512L

def contentDir    = blobStoreRoot.resolve("content")
def tmpDir        = contentDir.resolve("tmp")
def blobId        = UUID.randomUUID().toString()
def uuid          = UUID.randomUUID().toString()

// Mirrors temporaryContentPath and contentPath in FileBlobStore
def tmpBlobPath   = tmpDir.resolve("${blobId}.${uuid}.bytes")
def finalDir      = contentDir.resolve("2026/06/19/00/00")
def finalBlobPath = finalDir.resolve("${blobId}.bytes")

Files.createDirectories(tmpDir)
Files.createDirectories(finalDir)

println "=== FileBlobStore move test ==="
println "Blob store root : ${blobStoreRoot}"
println "File size       : ${fileSizeMB} MB"
println "Temp path       : ${tmpBlobPath}"
println "Final path      : ${finalBlobPath}"
println ""

// --- Phase 1: simulate ingester.ingestTo(temporaryBlobPath) ---
println "[1] Writing ${fileSizeMB} MB to temp path..."
def t0 = System.currentTimeMillis()
tmpBlobPath.withOutputStream { out ->
    def buf = new byte[1024 * 1024]  // 1 MB buffer
    new Random().nextBytes(buf)
    fileSizeMB.times { out.write(buf) }
}
def writeMs = System.currentTimeMillis() - t0
println "    Done in ${writeMs} ms  (${String.format('%.1f', fileSizeMB * 1000.0 / writeMs)} MB/s)"
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
println "Final file exists: ${Files.exists(finalBlobPath)}"
println "Final file size  : ${finalSize} bytes (expected ${fileSizeMB * 1024 * 1024})"
println "Temp file gone   : ${!Files.exists(tmpBlobPath)}"

// Cleanup
Files.deleteIfExists(finalBlobPath)
