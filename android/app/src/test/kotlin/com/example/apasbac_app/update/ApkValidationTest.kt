package com.example.apasbac_app.update

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ApkValidationTest {
    private fun apk(): File = File.createTempFile("update-test", ".apk").also { file ->
        file.deleteOnExit()
        ZipOutputStream(file.outputStream()).use { zip ->
            for (name in listOf("AndroidManifest.xml", "classes.dex")) {
                zip.putNextEntry(ZipEntry(name)); zip.write(byteArrayOf(1, 2, 3)); zip.closeEntry()
            }
        }
    }
    private fun hash(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun failure(reason: String, action: () -> Unit) {
        try { action(); fail("Expected $reason") } catch (e: UpdateFailure) { assertEquals(reason, e.reason) }
    }
    @Test fun validContainerAndHash() { val file = apk(); ApkValidation.checkFile(file, file.length(), hash(file)) }
    @Test fun wrongSha256() {
        val file = apk()
        failure("hash") { ApkValidation.checkFile(file, file.length(), "0".repeat(64)) }
        assertFalse("Corrupted APK must be deleted immediately", file.exists())
    }
    @Test fun incompleteApk() { val file = apk(); failure("incomplete") { ApkValidation.checkFile(file, file.length() + 1, hash(file)) } }
    @Test fun htmlIsNotApkEvenWithCorrectHash() {
        val file = apk(); file.writeText("<html>not an APK</html>")
        failure("invalid_apk") { ApkValidation.checkFile(file, file.length(), hash(file)) }
    }
    private fun identity(pkg: String = "app", code: Long = 12, signers: Set<String> = setOf("certificate"), min: Int = 24) =
        ApkValidation.checkIdentity("app", 11, setOf("certificate"), pkg, code, signers, 12, min, 24)
    @Test fun matchingPackageVersionCertificate() { identity() }
    @Test fun differentPackage() { failure("package") { identity(pkg = "other.app") } }
    @Test fun differentVersion() { failure("version") { identity(code = 13) } }
    @Test fun downgrade() { failure("version") { identity(code = 10) } }
    @Test fun unsignedApk() { failure("signature") { identity(signers = emptySet()) } }
    @Test fun incompatibleCertificate() { failure("signature") { identity(signers = setOf("attacker")) } }
    @Test fun incompatibleAndroid() { failure("sdk") { identity(min = 25) } }
}
