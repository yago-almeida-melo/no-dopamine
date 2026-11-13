package com.example.no_dopamine

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.no_dopamine.usage.UsageBridge

class MainActivity : FlutterActivity() {
    private var usageBridge: UsageBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usageBridge = UsageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usageBridge?.dispose()
        usageBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
