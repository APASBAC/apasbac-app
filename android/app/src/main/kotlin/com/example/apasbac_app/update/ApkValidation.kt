package com.example.apasbac_app.update

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile

class UpdateFailure(val reason: String) : Exception(reason)

/** Pure validation rules, also exercised by JVM tests. No installer side effects. */
object ApkValidation {
    fun checkFile(file: File, expectedSize: Long, expectedHash: String) {
        try { inspectFile(file, expectedSize, expectedHash) }
        catch (e: Exception) { file.delete(); throw e }
    }
    private fun inspectFile(file: File, expectedSize: Long, expectedHash: String) {
        if (!file.isFile || file.length() != expectedSize) throw UpdateFailure("incomplete")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(hash.toByteArray(), expectedHash.lowercase().toByteArray())) {
            throw UpdateFailure("hash")
        }
        try {
            ZipFile(file).use { zip ->
                if (zip.getEntry("AndroidManifest.xml") == null || zip.getEntry("classes.dex") == null) {
                    throw UpdateFailure("invalid_apk")
                }
            }
        } catch (e: UpdateFailure) { throw e }
        catch (_: Exception) { throw UpdateFailure("invalid_apk") }
    }

    fun checkIdentity(installedPackage: String, installedCode: Long, installedSigners: Set<String>,
        downloadedPackage: String, downloadedCode: Long, downloadedSigners: Set<String>,
        expectedCode: Long, apkMinSdk: Int, deviceSdk: Int) {
        if (downloadedPackage != installedPackage) throw UpdateFailure("package")
        if (downloadedCode != expectedCode || downloadedCode <= installedCode) throw UpdateFailure("version")
        if (apkMinSdk > deviceSdk) throw UpdateFailure("sdk")
        // Fail closed on key changes. Key rotation requires an explicit migration strategy.
        if (installedSigners.isEmpty() || installedSigners != downloadedSigners) throw UpdateFailure("signature")
    }
}
