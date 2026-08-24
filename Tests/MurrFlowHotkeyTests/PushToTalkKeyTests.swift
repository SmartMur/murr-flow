import Testing
@testable import MurrFlowHotkey

struct PushToTalkKeyTests {
    @Test
    func testFreshInstallDefaultsToRightOption() {
        #expect(PushToTalkKey.defaultKey == .rightOption)
        #expect(PushToTalkKey.defaultKey.rawValue == "rightOption")
        #expect(PushToTalkKey.defaultKey.displayName == "Right ⌥")
    }
}
