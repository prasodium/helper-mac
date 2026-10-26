import CryptoKit
import Foundation
import IOKit

/// Stable per-machine identifier for license binding.
///
/// Same derivation as the Electron app (sha256 of the lowercased
/// IOPlatformUUID), so one license maps to the same device in the store
/// whichever Helper build is used on this Mac.
public enum DeviceID {
    public static func current() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        var uuid = ""
        if service != 0,
           let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            uuid = value.lowercased()
        }
        if uuid.isEmpty { uuid = "\(ProcessInfo.processInfo.hostName)|\(ProcessInfo.processInfo.operatingSystemVersionString)" }
        return SHA256.hash(data: Data(uuid.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func name() -> String {
        let host = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName).split(separator: ".").first.map(String.init) ?? "Mac"
        return String(host.prefix(120))
    }
}
