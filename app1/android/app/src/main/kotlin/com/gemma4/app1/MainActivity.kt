package com.gemma4.app1

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var inferencePlugin: InferencePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        inferencePlugin = InferencePlugin(flutterEngine)
    }

    override fun onDestroy() {
        inferencePlugin?.dispose()
        inferencePlugin = null
        super.onDestroy()
    }
}
