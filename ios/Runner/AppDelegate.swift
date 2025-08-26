import UIKit
import Flutter
import flutter_downloader
// import flutter_sharing_intent

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)

    let controller = window.rootViewController as! FlutterViewController

    let flavorChannel = FlutterMethodChannel(
        name: "flavor",
        binaryMessenger: controller.binaryMessenger)

    flavorChannel.setMethodCallHandler({(call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        // Note: this method is invoked on the UI thread
        let flavor = Bundle.main.infoDictionary?["AppFlavor"]
        result(flavor)
    })
// TODO: add back when we have a working share extension
//    let sharingIntent = SwiftFlutterSharingIntentPlugin.instance
//     /// if the url is made from SwiftFlutterSharingIntentPlugin then handle it with plugin [SwiftFlutterSharingIntentPlugin]
//     if sharingIntent.hasSameSchemePrefix(url: url) {
//         return sharingIntent.application(app, open: url, options: options)
//     }


    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private func registerPlugins(registry: FlutterPluginRegistry) {
    if (!registry.hasPlugin("FlutterDownloaderPlugin")) {
       FlutterDownloaderPlugin.register(with: registry.registrar(forPlugin: "FlutterDownloaderPlugin")!)
    }
}
