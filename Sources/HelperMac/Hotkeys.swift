import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts (work while another app is frontmost).
final class Hotkeys {
    enum Action: UInt32, CaseIterable {
        case toggleWindow = 1, captureRegion, voice, analyzeScreen

        /// ⌃⌥ + key. Chosen to avoid clashing with system and common app shortcuts.
        var keyCode: UInt32 {
            switch self {
            case .toggleWindow: UInt32(kVK_Space)
            case .captureRegion: UInt32(kVK_ANSI_S)
            case .voice: UInt32(kVK_ANSI_V)
            case .analyzeScreen: UInt32(kVK_ANSI_A)
            }
        }

        var title: String {
            switch self {
            case .toggleWindow: "Show / hide Helper"
            case .captureRegion: "Capture a screen region"
            case .voice: "Start / stop voice input"
            case .analyzeScreen: "Analyze the whole screen"
            }
        }

        var display: String {
            switch self {
            case .toggleWindow: "⌃⌥Space"
            case .captureRegion: "⌃⌥S"
            case .voice: "⌃⌥V"
            case .analyzeScreen: "⌃⌥A"
            }
        }
    }

    static let shared = Hotkeys()
    var handler: ((Action) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = Action(rawValue: id.id) {
                DispatchQueue.main.async { Hotkeys.shared.handler?(action) }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x484C5052), id: action.rawValue) // 'HLPR'
            let status = RegisterEventHotKey(action.keyCode, UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }
}
