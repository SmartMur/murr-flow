import AppKit
import Carbon.HIToolbox

/// Which modifier key holds the microphone open.
public enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    /// The shortcut used when no preference has been saved yet.
    public static let defaultKey: Self = .rightOption

    public var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-dependent bit for this specific physical key.
    ///
    /// The public Option and Command masks combine both sides. These IOKit device masks
    /// retain the distinction, preventing the microphone from sticking open when the
    /// matching left-hand modifier is also held.
    public var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker.
    public var shouldConsumeEvent: Bool { self != .fn }
}
