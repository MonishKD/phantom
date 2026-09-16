import CoreLocation
import Foundation

/// A device as reported by the helper (`devices` events and `list` replies).
struct DeviceInfo: Decodable, Identifiable, Hashable {
    let udid: String
    let name: String
    let model: String?
    let iosVersion: String?
    let connection: String
    let deviceClass: String?
    let paired: Bool
    let developerMode: Bool?
    let problem: String?

    var id: String { udid }
    var displayName: String { name.isEmpty ? udid : name }

    /// What to call this device in a sentence.
    var noun: String {
        switch deviceClass {
        case "iPhone": "iPhone"
        case "iPad": "iPad"
        case "iPod": "iPod touch"
        case "AppleTV": "Apple TV"
        case "Watch": "Apple Watch"
        case "RealityDevice": "Vision Pro"
        default: "device"
        }
    }

    var icon: String {
        switch deviceClass {
        case "iPhone": "iphone"
        case "iPad": "ipad"
        case "iPod": "ipodtouch"
        case "AppleTV": "appletv"
        case "Watch": "applewatch"
        case "RealityDevice": "visionpro"
        default: "cable.connector"
        }
    }

    /// For example "iPadOS 27.0 · USB".
    var systemAndConnection: String {
        [iosVersion.map { "\(osName) \($0)" }, connection == "USB" ? "USB" : "Wi-Fi"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var osName: String {
        switch deviceClass {
        case "iPad": "iPadOS"
        case "AppleTV": "tvOS"
        case "Watch": "watchOS"
        case "RealityDevice": "visionOS"
        default: "iOS"
        }
    }
}

enum SessionPhase: String, Decodable {
    case idle, connecting, mounting, tunneling, active, reconnecting, error
}

/// Per-device spoofing session state pushed by the helper.
struct SessionStatus: Decodable {
    let udid: String
    let phase: SessionPhase
    let message: String?
    let latitude: Double?
    let longitude: Double?
}

struct HelperFailure: Decodable, Error, Equatable {
    let code: String
    let message: String

    var title: String {
        switch code {
        case "NO_DEVICE": "Device not found"
        case "PAIRING": "Device isn't paired with this Mac"
        case "LOCKED": "Device is locked"
        case "DEVELOPER_MODE": "Developer Mode is off"
        case "DISK_IMAGE": "Couldn't mount the developer disk image"
        case "TUNNEL": "Couldn't open a tunnel to the device"
        case "CONNECTION": "Lost connection to the device"
        case "HELPER_DOWN": "Device helper isn't running"
        case "INVALID_COORDINATE": "That isn't a valid location"
        default: "Something went wrong"
        }
    }

    /// `noun` names the connected device ("iPhone", "iPad", …) so hints read naturally.
    func hint(_ noun: String) -> String? {
        switch code {
        case "NO_DEVICE": "Connect the \(noun) with a cable, unlock it, and pick it in the sidebar."
        case "PAIRING": "Unlock the \(noun), tap Trust when asked, and enter the passcode."
        case "LOCKED": "Unlock the \(noun) and try again."
        case "DEVELOPER_MODE": "On the \(noun): Settings › Privacy & Security › Developer Mode › On. It restarts, then confirm Turn On."
        case "DISK_IMAGE": "Keep this Mac online. The image is downloaded and signed by Apple the first time."
        case "TUNNEL": "Unplug and reconnect the cable, unlock the \(noun), and try again."
        case "CONNECTION": "Check the cable and try again. Phantom reconnects on its own when it can."
        case "HELPER_DOWN": "Use Restart Helper in the sidebar."
        default: nil
        }
    }
}

/// One JSON line from the helper: a reply (has `id`) or an event (has `event`).
struct HelperMessage: Decodable {
    let id: Int?
    let ok: Bool?
    let superseded: Bool?
    let error: HelperFailure?
    let event: String?
    let devices: [DeviceInfo]?
    let status: SessionStatus?
    let message: String?

    static func failure(_ code: String, _ message: String) -> HelperMessage {
        HelperMessage(
            id: nil, ok: false, superseded: nil, error: HelperFailure(code: code, message: message),
            event: nil, devices: nil, status: nil, message: nil
        )
    }
}

extension CLLocationCoordinate2D {
    var formatted: String { String(format: "%.6f, %.6f", latitude, longitude) }

    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
