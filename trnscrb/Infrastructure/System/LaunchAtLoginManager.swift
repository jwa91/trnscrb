import ServiceManagement

/// Applies launch-at-login settings via SMAppService.
struct LaunchAtLoginManager: LaunchAtLoginGateway {
    func apply(enabled: Bool) async throws {
        let service: SMAppService = SMAppService.mainApp

        switch (enabled, service.status) {
        case (true, .enabled), (true, .requiresApproval):
            return
        case (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try await service.unregister()
        }
    }
}
