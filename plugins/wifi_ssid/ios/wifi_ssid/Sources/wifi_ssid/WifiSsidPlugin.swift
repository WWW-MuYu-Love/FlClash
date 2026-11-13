import Flutter
import NetworkExtension

public class WifiSsidPlugin: NSObject, FlutterPlugin {

    private enum Method {
        static let getSsid = "getSsid"
        static let checkPermission = "checkPermission"
        static let requestPermission = "requestPermission"
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "wifi_ssid", binaryMessenger: registrar.messenger()
        )
        let instance = WifiSsidPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case Method.getSsid:
            getSsid(result: result)
        case Method.checkPermission, Method.requestPermission:
            // fetchCurrent answers once the app holds the wifi-info
            // entitlement and an installed VPN configuration, so there is no
            // user-grantable permission on this path.
            result(WifiSsidPermission.granted.rawValue)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private enum WifiSsidPermission: Int {
        // Values must match WifiSsidPermission.index in Dart.
        case granted = 0
        case denied = 1
        case permanentlyDenied = 2
    }

    private func getSsid(result: @escaping FlutterResult) {
        // fetchCurrent answers off the calling thread; the result goes back
        // on the main queue, never inline on the platform thread.
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                result(network?.ssid)
            }
        }
    }
}
