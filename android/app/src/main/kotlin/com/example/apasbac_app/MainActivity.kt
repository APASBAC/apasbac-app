package com.example.apasbac_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.apasbac_app.update.UpdateBridge

class MainActivity : FlutterActivity() {
    private var updates: UpdateBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updates = UpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onResume() { super.onResume(); updates?.resume() }
    override fun onPause() { updates?.pause(); super.onPause() }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updates?.dispose(); updates = null; super.cleanUpFlutterEngine(flutterEngine)
    }
}
