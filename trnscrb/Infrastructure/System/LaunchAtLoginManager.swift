import ServiceManagement

/// Applies launch-at-login settings via SMAppService.
struct LaunchAtLoginManager: LaunchAtLoginGateway {
    func apply(enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }
}
