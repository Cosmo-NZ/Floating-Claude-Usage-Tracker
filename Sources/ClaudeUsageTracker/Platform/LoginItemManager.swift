import Foundation
import ServiceManagement

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("[loginItem] \(error.localizedDescription)\n".utf8))
        }
    }
}
