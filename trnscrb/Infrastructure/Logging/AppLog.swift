import OSLog

enum AppLog {
    private static let subsystem: String = AppIdentity.loggerSubsystem

    static let pipeline: Logger = Logger(subsystem: subsystem, category: "pipeline")
    static let network: Logger = Logger(subsystem: subsystem, category: "network")
    static let ui: Logger = Logger(subsystem: subsystem, category: "ui")
    static let delivery: Logger = Logger(subsystem: subsystem, category: "delivery")
    static let config: Logger = Logger(subsystem: subsystem, category: "config")
}
