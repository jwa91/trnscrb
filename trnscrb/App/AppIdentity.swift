enum AppIdentity {
    static let bundleIdentifier: String = "com.janwillemaltink.trnscrb"
    static let loggerSubsystem: String = bundleIdentifier
    static let keychainService: String = "\(bundleIdentifier).credentials.v3"
    static let privacyPolicyURLString: String = "https://janwillemaltink.com/trnscrb/privacy"
}
