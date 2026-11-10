package com.ccloud.ccloud

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ccloud/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> {
                        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(
                            uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
