package com.example.apasbac_app.update

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

@Suppress("DEPRECATION")
class UpdateVerifier(private val context: Context) {
    fun verify(file: File, manifest: UpdateManifest) {
        try {
            ApkValidation.checkFile(file, manifest.size, manifest.sha256)
            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
            val archive = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
                ?: throw UpdateFailure("invalid_apk")
            if (!archive.splitNames.isNullOrEmpty()) throw UpdateFailure("invalid_apk")
            val store = UpdateStore(context)
            val installed = store.installed()
            ApkValidation.checkIdentity(installed.packageName, store.code(installed), signers(installed),
                archive.packageName, store.code(archive), signers(archive), manifest.code,
                archive.applicationInfo?.minSdkVersion ?: throw UpdateFailure("invalid_apk"), Build.VERSION.SDK_INT)
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }
    private fun signers(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { it.toCharsString() }?.toSet() ?: emptySet()
}
