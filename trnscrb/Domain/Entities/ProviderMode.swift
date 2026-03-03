import Foundation

/// Processing provider mode for a media type.
///
/// Keep this enum extensible because settings UI intentionally models provider
/// choice as an option list rather than a boolean toggle.
public enum ProviderMode: String, Sendable, Equatable, CaseIterable, Hashable {
    /// Process through the cloud Mistral pipeline.
    case mistral
    /// Process locally using Apple on-device frameworks.
    case localApple = "local"
}
