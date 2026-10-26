import Foundation

/// Where the license state lives. The key goes in the Keychain in the app;
/// tests substitute an in-memory store.
public protocol LicenseStorage: AnyObject {
    var licenseKey: String { get set }
    var deviceID: String { get set }
    var lastCheckAt: Date? { get set }
    var productName: String { get set }
    func clear()
}

public final class DefaultsLicenseStorage: LicenseStorage {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var licenseKey: String {
        get { KeychainStore.get("license-key") }
        set { KeychainStore.set(newValue, for: "license-key") }
    }
    public var deviceID: String {
        get { defaults.string(forKey: "license.deviceID") ?? "" }
        set { defaults.set(newValue, forKey: "license.deviceID") }
    }
    public var lastCheckAt: Date? {
        get { defaults.object(forKey: "license.lastCheckAt") as? Date }
        set { defaults.set(newValue, forKey: "license.lastCheckAt") }
    }
    public var productName: String {
        get { defaults.string(forKey: "license.productName") ?? "" }
        set { defaults.set(newValue, forKey: "license.productName") }
    }
    public func clear() {
        KeychainStore.remove("license-key")
        ["license.deviceID", "license.lastCheckAt", "license.productName"].forEach { defaults.removeObject(forKey: $0) }
    }
}

/// HTTP seam so the license flow can be tested without a network.
public protocol LicenseTransport: Sendable {
    func post(_ url: URL, json: [String: Any]) async throws -> (status: Int, body: Data)
}

public struct URLSessionTransport: LicenseTransport {
    public init() {}
    public func post(_ url: URL, json: [String: Any]) async throws -> (status: Int, body: Data) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

public struct AccessResult: Sendable, Equatable {
    public enum Reason: String, Sendable { case ok, free, notActivated, suspended, blocked, updateRequired, offlineExpired }
    public var allowed: Bool
    public var reason: Reason
    public var message: String
    public var offline: Bool = false
    public var plan: Plan
}

public struct ActivationResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    public var productName: String = ""
}

/// "1 payment = 1 device" licensing, speaking the same API as the Helper
/// Store worker (/license/activate, /heartbeat, /deactivate).
///
/// No key means the Free plan (no server contact). A stored key means Pro and
/// is re-verified on launch and every 15 minutes; offline use is tolerated
/// for 7 days.
public final class LicenseManager: @unchecked Sendable {
    public static let keyPattern = #"^HLP-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
    public static let offlineGraceDays = 7.0
    public static let heartbeatInterval: TimeInterval = 15 * 60
    public static let defaultServer = "https://helper-store-worker.helper-store.workers.dev/api/v1/license"

    public let serverURL: String
    private let storage: LicenseStorage
    private let transport: LicenseTransport
    private let appVersion: String
    private let deviceID: () -> String
    private let deviceName: () -> String
    private let now: () -> Date

    public init(serverURL: String? = nil,
                storage: LicenseStorage = DefaultsLicenseStorage(),
                transport: LicenseTransport = URLSessionTransport(),
                appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
                deviceID: @escaping () -> String = DeviceID.current,
                deviceName: @escaping () -> String = DeviceID.name,
                now: @escaping () -> Date = Date.init) {
        self.serverURL = serverURL ?? ProcessInfo.processInfo.environment["HELPER_LICENSE_SERVER"] ?? Self.defaultServer
        self.storage = storage
        self.transport = transport
        self.appVersion = appVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.now = now
    }

    // MARK: State

    public var storedKey: String { storage.licenseKey }
    public var isActivated: Bool { !storage.licenseKey.isEmpty }
    public var plan: Plan { isActivated ? .pro : .free }
    public var productName: String { storage.productName }
    public var lastCheckAt: Date? { storage.lastCheckAt }

    public var keyPreview: String {
        let key = storage.licenseKey
        return key.isEmpty ? "" : key.prefix(7) + "…" + key.suffix(4)
    }

    public static func isValidKeyFormat(_ key: String) -> Bool {
        key.range(of: keyPattern, options: .regularExpression) != nil
    }

    // MARK: Server calls

    private func url(_ path: String) -> URL { URL(string: "\(serverURL)/\(path)")! }

    private static func serverMessage(_ body: Data, fallback: String) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let err = obj["error"] as? [String: Any], let message = err["message"] as? String { return message }
        return fallback
    }

    public func activate(_ rawKey: String) async -> ActivationResult {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.isValidKeyFormat(key) else {
            return .init(ok: false, message: "That doesn’t look like a Helper license key. It should look like HLP-AB12-CD34-EF56.")
        }
        let id = deviceID()
        do {
            let (status, body) = try await transport.post(url("activate"), json: [
                "licenseKey": key, "deviceId": id, "deviceName": deviceName(),
                "platform": "macos", "appVersion": appVersion,
            ])
            if (200..<300).contains(status) {
                storage.licenseKey = key
                storage.deviceID = id
                storage.lastCheckAt = now()
                if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let data = obj["data"] as? [String: Any], let license = data["license"] as? [String: Any],
                   let product = license["product"] as? [String: Any], let name = product["name"] as? String {
                    storage.productName = name
                }
                return .init(ok: true, message: "", productName: storage.productName)
            }
            if [403, 404, 409].contains(status) {
                return .init(ok: false, message: Self.serverMessage(body, fallback: "Activation failed."))
            }
        } catch {}
        return .init(ok: false, message: "Couldn’t reach the license server. Check your internet connection and try again.")
    }

    /// Verifies the stored key with the server. Missing key => Free plan.
    public func checkAccess() async -> AccessResult {
        guard isActivated else { return .init(allowed: true, reason: .free, message: "", plan: .free) }
        return await heartbeat()
    }

    public func heartbeat() async -> AccessResult {
        let key = storage.licenseKey
        guard !key.isEmpty else { return .init(allowed: true, reason: .free, message: "", plan: .free) }
        let id = deviceID()
        if id != storage.deviceID {
            // Settings copied from another Mac: it must activate as its own device.
            storage.clear()
            return .init(allowed: false, reason: .notActivated,
                         message: "This copy of Helper was moved to a different device. Please activate it with your license key.", plan: .free)
        }
        do {
            let (status, body) = try await transport.post(url("heartbeat"), json: [
                "licenseKey": key, "deviceId": id, "appVersion": appVersion,
            ])
            if (200..<300).contains(status) {
                storage.lastCheckAt = now()
                return .init(allowed: true, reason: .ok, message: "", plan: .pro)
            }
            if status == 403 {
                let message = Self.serverMessage(body, fallback: "This license is no longer active.")
                let reason: AccessResult.Reason = message.range(of: "newer version of the app", options: .caseInsensitive) != nil
                    ? .updateRequired
                    : (message.range(of: "suspend", options: .caseInsensitive) != nil ? .suspended : .blocked)
                return .init(allowed: false, reason: reason, message: message, plan: .free)
            }
            if status == 404 {
                storage.clear()
                return .init(allowed: false, reason: .notActivated,
                             message: "This license key is no longer valid. Please activate again.", plan: .free)
            }
        } catch {}
        // Unreachable server: tolerate a limited time offline.
        let days = now().timeIntervalSince(storage.lastCheckAt ?? .distantPast) / 86_400
        if days <= Self.offlineGraceDays {
            return .init(allowed: true, reason: .ok, message: "", offline: true, plan: .pro)
        }
        return .init(allowed: false, reason: .offlineExpired,
                     message: "Helper couldn’t verify your license for over 7 days. Connect to the internet once to keep using Pro.", plan: .free)
    }

    /// Signs this device out, freeing its slot on the server.
    public func deactivate() async {
        let key = storage.licenseKey
        let id = storage.deviceID
        storage.clear()
        guard !key.isEmpty, !id.isEmpty else { return }
        _ = try? await transport.post(url("deactivate"), json: ["licenseKey": key, "deviceId": id])
    }
}
