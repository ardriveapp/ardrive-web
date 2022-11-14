package io.ardrive.app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterFragmentActivity() {
  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "channel").setMethodCallHandler {
      call, result -> result.success(BuildConfig.FLAVOR)
    }
  }
}
