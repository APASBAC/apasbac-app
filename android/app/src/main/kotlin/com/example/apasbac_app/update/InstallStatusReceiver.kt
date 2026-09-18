package com.example.apasbac_app.update

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = UpdateStore(context)
        val sessionId = store.prefs.getInt("sessionId", -1)
        if (sessionId < 0 || intent.action != "${context.packageName}.UPDATE_STATUS.$sessionId" ||
            intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1) != sessionId) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val action = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    else intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (action == null) { store.fail("install"); return }
                store.prefs.edit().putString("pendingAction", action.toUri(Intent.URI_INTENT_SCHEME)).commit()
                store.state("installing", "Confirme a atualização na tela do Android.")
                val activity = UpdateInstaller.foreground.get()
                if (activity != null && !activity.isFinishing) {
                    try {
                        activity.startActivity(action)
                        store.prefs.edit().remove("pendingAction").commit()
                    } catch (_: Exception) { UpdateNotifications.show(context, "Toque para confirmar a atualização.", action) }
                } else UpdateNotifications.show(context, "Toque para confirmar a atualização.", action)
            }
            PackageInstaller.STATUS_SUCCESS -> {
                // The old process can die before this callback. Startup also detects success.
                store.recover()
            }
            else -> store.fail("install")
        }
    }
}
