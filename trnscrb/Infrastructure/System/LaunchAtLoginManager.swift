import ServiceManagement

/// Applies launch-at-login settings via SMAppService.
enum LaunchAtLoginManager {
    static func apply(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
