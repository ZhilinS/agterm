import agtermCore
import Foundation

// Fork: kept out of upstream's SettingsModel.swift.
extension SettingsModel {
    func applyRenameOnDoubleClick() {
        GhosttyApp.shared.setRenameOnDoubleClick(settings.renameOnDoubleClick ?? true)
    }
}
