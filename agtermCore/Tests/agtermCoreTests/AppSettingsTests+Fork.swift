import Foundation
import Testing
@testable import agtermCore

// Fork: kept out of upstream's AppSettingsTests.swift.
extension AppSettingsTests {
    @Test func renameOnDoubleClickDefaultsOnAndIsNotAConfigLine() throws {
        #expect(AppSettings().renameOnDoubleClick == nil)
        let decoded = try JSONDecoder().decode(AppSettings.self,
                                               from: JSONEncoder().encode(AppSettings(renameOnDoubleClick: false)))
        #expect(decoded.renameOnDoubleClick == false)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"Nord"}"#.utf8))
        #expect(legacy.renameOnDoubleClick == nil)
        #expect(AppSettings(renameOnDoubleClick: false).ghosttyConfigLines()
            == ["mouse-scroll-multiplier = 3", "right-click-action = paste"])
    }
}
