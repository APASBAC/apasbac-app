package com.example.apasbac_app.update

import org.json.JSONObject
import java.net.URI

data class UpdateManifest(val code: Long, val name: String, val minimum: Long,
    val mandatory: Boolean, val url: String, val sha256: String, val size: Long,
    val json: String) {
    companion object {
        fun parse(raw: String): UpdateManifest {
            require(raw.length <= 65536)
            val j = JSONObject(raw)
            fun number(key: String, max: Long): Long {
                val value = j.get(key)
                require(value is Int || value is Long)
                return (value as Number).toLong().also { require(it in 1..max) }
            }
            number("schemaVersion", 1)
            require(j.getString("channel") in listOf("stable", "beta"))
            val code = number("versionCode", 2100000000)
            val minimum = number("minimumSupportedVersionCode", code)
            require(j.get("mandatory") is Boolean)
            val name = j.getString("versionName").also { require(it.isNotBlank() && it.length <= 100) }
            val url = j.getString("apkUrl")
            val uri = URI(url)
            require(uri.scheme == "https" && uri.host == "github.com" && uri.port == -1 &&
                uri.userInfo == null && uri.query == null && uri.fragment == null &&
                Regex("/APASBAC/apasbac-app/releases/download/[^/]+/[^/]+\\.apk").matches(uri.path))
            val hash = j.getString("sha256").lowercase().also { require(Regex("[a-f0-9]{64}").matches(it)) }
            val size = number("sizeBytes", 1073741824)
            return UpdateManifest(code, name, minimum, j.getBoolean("mandatory"), url, hash, size, raw)
        }
    }
}
