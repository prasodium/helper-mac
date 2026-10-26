import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts (work while another app is frontmost).
final class Hotkeys {
    enum Action: UInt32, CaseIterable {
        case toggleWindow = 1, captureRegion, voice, analyzeScreen, meetingAudio, toggleWindowCommand, quit

        /// ⌃⌥ + key for most actions (chosen to avoid clashing with system and common app shortcuts);
        /// ⌘⇧H and ⌘⇧Q match the Electron app.
        var modifiers: UInt32 {
            switch self {
            case .toggleWindowCommand, .quit: UInt32(cmdKey | shiftKey)
            default: UInt32(controlKey | optionKey)
            }
        }

        var keyCode: UInt32 {
            switch self {
            case .toggleWindow: UInt32(kVK_Space)
            case .captureRegion: UInt32(kVK_ANSI_S)
            case .voice: UInt32(kVK_ANSI_V)
            case .analyzeScreen: UInt32(kVK_ANSI_A)
            case .meetingAudio: UInt32(kVK_ANSI_M)
            case .toggleWindowCommand: UInt32(kVK_ANSI_H)
            case .quit: UInt32(kVK_ANSI_Q)
            }
        }

        var title: String {
            switch self {
            case .toggleWindow: "Show / hide Helper"
            case .captureRegion: "Capture a screen region"
            case .voice: "Start / stop voice input"
            case .analyzeScreen: "Analyze the whole screen"
            case .meetingAudio: "Answer from meeting audio"
            case .toggleWindowCommand: "Show / hide Helper"
            case .quit: "Quit Helper"
            }
        }

        var display: String {
            switch self {
            case .toggleWindow: "⌃⌥Space"
            case .captureRegion: "⌃⌥S"
            case .voice: "⌃⌥V"
            case .analyzeScreen: "⌃⌥A"
            case .meetingAudio: "⌃⌥M"
            case .toggleWindowCommand: "⌘⇧H"
            case .quit: "⌘⇧Q"
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
            let status = RegisterEventHotKey(action.keyCode, action.modifiers, id,
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
