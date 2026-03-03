import Foundation

protocol SecretStore: Sendable {
    func get(for key: SecretKey) throws -> String?
    func set(_ value: String, for key: SecretKey) throws
    func remove(for key: SecretKey) throws
}
