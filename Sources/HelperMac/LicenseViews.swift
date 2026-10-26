import HelperCore
import SwiftUI

struct UpsellSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let feature: Feature

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Unlock Helper Pro").font(.title2.weight(.semibold))
            Text("\(feature.label) is a Pro feature.").foregroundStyle(.secondary)
            Text("One activation key unlocks every feature on this Mac.")
                .font(.callout).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button { state.openStore(); dismiss() } label: { Text("Get Pro").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { dismiss(); state.showLicenseEntry = true } label: { Text("I have a key").frame(maxWidth: .infinity) }
                    .controlSize(.large)
                Button("Not now") { dismiss() }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}

struct LicenseEntrySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Local private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activate Helper Pro").font(.title3.weight(.semibold))
            Text("Enter the activation key from your purchase. It looks like HLP-AB12-CD34-EF56.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("HLP-XXXX-XXXX-XXXX", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .onSubmit { Task { await state.activate(key) } }
            if !state.licenseMessage.isEmpty {
                Label(state.licenseMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Get a key") { state.openStore() }.buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { state.licenseMessage = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await state.activate(key) }
                } label: {
                    if state.licenseBusy { ProgressView().controlSize(.small) } else { Text("Activate") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || state.licenseBusy)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

/// Shown over the window when the server says the license can't be used
/// (suspended, revoked, moved to another Mac, too old a build...).
struct LicenseBlockedView: View {
    @Environment(AppState.self) private var state
    let result: AccessResult

    private var title: String {
        switch result.reason {
        case .suspended: "License suspended"
        case .updateRequired: "Update required"
        case .offlineExpired: "Couldn't verify your license"
        case .notActivated: "Activation needed"
        default: "License unavailable"
        }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(.orange)
                Text(title).font(.title2.weight(.semibold))
                Text(result.message.isEmpty ? "Your Pro license couldn't be verified." : result.message)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await state.verifyLicense() } }
                    Button("Use Free plan") { Task { await state.deactivate() } }
                    Button("Enter a key") { state.showLicenseEntry = true }.buttonStyle(.borderedProminent)
                }
            }
            .padding(30)
        }
    }
}
