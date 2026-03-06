import Foundation
import Testing

@testable import trnscrb

struct KeychainStoreTests {
    /// Each test gets a unique service name to avoid parallel test interference.
    private static func makeStore() -> KeychainStore {
        KeychainStore(service: "com.janwillemaltink.trnscrb.test.\(UUID().uuidString)")
    }

    @Test func setAndGetSecret() throws {
        let store = Self.makeStore()
        try store.set("test-api-key", for: .mistralAPIKey)
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == "test-api-key")
        try store.remove(for: .mistralAPIKey)
    }

    @Test func getNonexistentReturnsNil() throws {
        let store = Self.makeStore()
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == nil)
    }

    @Test func updateExistingSecret() throws {
        let store = Self.makeStore()
        try store.set("old-key", for: .s3SecretKey)
        try store.set("new-key", for: .s3SecretKey)
        let value: String? = try store.get(for: .s3SecretKey)
        #expect(value == "new-key")
        try store.remove(for: .s3SecretKey)
    }

    @Test func removeSecret() throws {
        let store = Self.makeStore()
        try store.set("to-remove", for: .mistralAPIKey)
        try store.remove(for: .mistralAPIKey)
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == nil)
    }

    @Test func removeNonexistentDoesNotThrow() throws {
        let store = Self.makeStore()
        try store.remove(for: .mistralAPIKey)
    }
}
