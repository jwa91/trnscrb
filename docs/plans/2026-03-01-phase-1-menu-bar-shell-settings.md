# Phase 1 — Menu Bar Shell + Settings

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the menu bar app shell (NSStatusItem + NSPopover), implement settings persistence (TOML config file + macOS Keychain), and create the settings UI — giving us a visible, interactive app that can store credentials for Phase 2.

**Architecture:** AppDelegate is the composition root — it creates the NSStatusItem, manages the NSPopover, and wires all dependencies. TOMLConfigManager reads/writes a flat TOML config file at `~/.config/trnscrb/config.toml` (XDG-compliant). KeychainStore wraps the Security framework for API key storage. SettingsViewModel bridges SettingsGateway to SwiftUI. No external dependencies — TOML serialization is hand-rolled for the flat key-value format.

**Tech Stack:** SwiftUI, AppKit (NSStatusItem, NSPopover, NSHostingController), Security framework (Keychain), Foundation (FileManager)

---

## Task 1: KeychainStore (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Keychain/KeychainStore.swift`
- Create: `Tests/Infrastructure/KeychainStoreTests.swift`

### Step 1: Write failing tests

Create `Tests/Infrastructure/KeychainStoreTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct KeychainStoreTests {
    private let store: KeychainStore = KeychainStore(service: "com.trnscrb.test")

    private func cleanup() throws {
        try store.remove(for: .mistralAPIKey)
        try store.remove(for: .s3SecretKey)
    }

    @Test func setAndGetSecret() throws {
        try cleanup()
        try store.set("test-api-key", for: .mistralAPIKey)
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == "test-api-key")
        try cleanup()
    }

    @Test func getNonexistentReturnsNil() throws {
        try cleanup()
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == nil)
    }

    @Test func updateExistingSecret() throws {
        try cleanup()
        try store.set("old-key", for: .s3SecretKey)
        try store.set("new-key", for: .s3SecretKey)
        let value: String? = try store.get(for: .s3SecretKey)
        #expect(value == "new-key")
        try cleanup()
    }

    @Test func removeSecret() throws {
        try cleanup()
        try store.set("to-remove", for: .mistralAPIKey)
        try store.remove(for: .mistralAPIKey)
        let value: String? = try store.get(for: .mistralAPIKey)
        #expect(value == nil)
    }

    @Test func removeNonexistentDoesNotThrow() throws {
        try cleanup()
        try store.remove(for: .mistralAPIKey)
    }
}
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter KeychainStoreTests 2>&1 | tail -20`
Expected: Compilation error — `KeychainStore` doesn't exist yet.

### Step 3: Implement KeychainStore

Create `trnscrb/Infrastructure/Keychain/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Errors from Keychain operations.
public enum KeychainError: Error, Sendable {
    /// An unexpected Security framework status code.
    case unexpectedStatus(OSStatus)
    /// Could not convert Keychain data to/from UTF-8.
    case dataConversionFailed
}

/// Wraps the macOS Keychain for storing and retrieving secrets.
///
/// Each secret is stored as a generic password keyed by service + account.
/// The service name scopes all items to this app (or a test namespace).
public struct KeychainStore: Sendable {
    /// Keychain service name used to scope stored items.
    private let service: String

    /// Creates a KeychainStore scoped to the given service name.
    /// - Parameter service: Keychain service identifier (default: `"com.trnscrb"`).
    public init(service: String = "com.trnscrb") {
        self.service = service
    }

    /// Retrieves a secret from the Keychain.
    /// - Parameter key: Which secret to retrieve.
    /// - Returns: The secret string, or `nil` if not found.
    public func get(for key: SecretKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Stores or updates a secret in the Keychain.
    /// - Parameters:
    ///   - value: The secret string to store.
    ///   - key: Which secret to store.
    public func set(_ value: String, for key: SecretKey) throws {
        guard let data: Data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Try to update an existing item first.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus: OSStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Item doesn't exist yet — add it.
            var addQuery: [String: Any] = query
            addQuery[kSecValueData as String] = data
            let addStatus: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Removes a secret from the Keychain. Does nothing if the item doesn't exist.
    /// - Parameter key: Which secret to remove.
    public func remove(for key: SecretKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status: OSStatus = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

### Step 4: Run tests to verify they pass

Run: `swift test --filter KeychainStoreTests 2>&1 | tail -20`
Expected: All 5 tests pass.

### Step 5: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Keychain/ 2>&1`
Expected: No violations.

### Step 6: Commit

```bash
git add trnscrb/Infrastructure/Keychain/KeychainStore.swift Tests/Infrastructure/KeychainStoreTests.swift
git commit -m "feat(infra): add KeychainStore with Security framework wrapper"
```

---

## Task 2: TOMLConfigManager (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Config/TOMLConfigManager.swift`
- Create: `Tests/Infrastructure/TOMLConfigManagerTests.swift`

**Context:** TOMLConfigManager implements `SettingsGateway`. It handles TOML config read/write itself, and delegates `getSecret`/`setSecret`/`removeSecret` to the injected `KeychainStore`. The TOML format is flat key-value (no nested tables), so serialization is hand-rolled. Config path follows XDG: `$XDG_CONFIG_HOME/trnscrb/config.toml` defaulting to `~/.config/trnscrb/config.toml`.

### Step 1: Write failing tests

Create `Tests/Infrastructure/TOMLConfigManagerTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct TOMLConfigManagerTests {
    /// Creates a manager backed by a temporary directory, cleaned up automatically.
    private func makeManager() throws -> (TOMLConfigManager, URL) {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        return (manager, tempDir)
    }

    private func cleanupDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Load

    @Test func loadFromNonexistentFileReturnsDefaults() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = try await manager.loadSettings()
        #expect(settings == AppSettings())
    }

    // MARK: - Save and round-trip

    @Test func saveCreatesConfigFile() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        try await manager.saveSettings(AppSettings())
        let filePath: String = tempDir.appending(path: "config.toml").path()
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    @Test func roundTripPreservesAllFields() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let original: AppSettings = AppSettings(
            s3EndpointURL: "https://nbg1.your-objectstorage.com",
            s3AccessKey: "AKID123",
            s3BucketName: "my-bucket",
            s3Region: "eu-central-1",
            s3PathPrefix: "uploads/",
            outputMode: .saveToFolder,
            saveFolderPath: "~/Desktop/output/",
            fileRetentionHours: 48,
            launchAtLogin: true
        )
        try await manager.saveSettings(original)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded == original)
    }

    @Test func roundTripWithDefaultValues() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let defaults: AppSettings = AppSettings()
        try await manager.saveSettings(defaults)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded == defaults)
    }

    // MARK: - TOML format

    @Test func savedFileIsTOMLFormat() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://example.com",
            s3BucketName: "bucket",
            outputMode: .both,
            fileRetentionHours: 12,
            launchAtLogin: true
        )
        try await manager.saveSettings(settings)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        // Verify key TOML patterns exist
        #expect(content.contains("s3_endpoint_url = \"https://example.com\""))
        #expect(content.contains("s3_bucket_name = \"bucket\""))
        #expect(content.contains("output_mode = \"both\""))
        #expect(content.contains("file_retention_hours = 12"))
        #expect(content.contains("launch_at_login = true"))
    }

    // MARK: - Edge cases

    @Test func handlesQuotesInStringValues() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://example.com/path?a=1&b=\"2\""
        )
        try await manager.saveSettings(settings)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded.s3EndpointURL == settings.s3EndpointURL)
    }

    @Test func ignoresCommentAndBlankLines() async throws {
        let (_, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        // Write a TOML file with comments and blank lines manually
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        # trnscrb config
        s3_endpoint_url = "https://test.com"

        # S3 settings
        s3_bucket_name = "test-bucket"
        file_retention_hours = 72
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded.s3EndpointURL == "https://test.com")
        #expect(loaded.s3BucketName == "test-bucket")
        #expect(loaded.fileRetentionHours == 72)
        // Fields not in file should be defaults
        #expect(loaded.s3Region == "auto")
        #expect(loaded.outputMode == .clipboard)
    }
}
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter TOMLConfigManagerTests 2>&1 | tail -20`
Expected: Compilation error — `TOMLConfigManager` doesn't exist yet.

### Step 3: Implement TOMLConfigManager

Create `trnscrb/Infrastructure/Config/TOMLConfigManager.swift`:

```swift
import Foundation

/// Errors from config file operations.
public enum ConfigError: Error, Sendable {
    /// The config file content could not be parsed.
    case parseError(String)
}

/// Reads and writes application settings to a TOML config file.
///
/// Config path follows XDG: `$XDG_CONFIG_HOME/trnscrb/config.toml`,
/// defaulting to `~/.config/trnscrb/config.toml`.
/// Secrets are delegated to the injected `KeychainStore`.
public final class TOMLConfigManager: SettingsGateway, @unchecked Sendable {
    /// Directory containing `config.toml`.
    private let configDirectory: URL
    /// Keychain wrapper for secret storage.
    private let keychainStore: KeychainStore

    /// Creates a config manager.
    /// - Parameters:
    ///   - configDirectory: Override for config directory (defaults to XDG path).
    ///   - keychainStore: Keychain wrapper for secret storage.
    public init(
        configDirectory: URL? = nil,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        if let configDirectory {
            self.configDirectory = configDirectory
        } else {
            if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
                self.configDirectory = URL(filePath: xdg).appending(path: "trnscrb")
            } else {
                self.configDirectory = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: ".config/trnscrb")
            }
        }
        self.keychainStore = keychainStore
    }

    /// URL of the TOML config file.
    private var configFileURL: URL {
        configDirectory.appending(path: "config.toml")
    }

    // MARK: - SettingsGateway conformance

    /// Loads settings from the TOML config file. Returns defaults if file doesn't exist.
    public func loadSettings() async throws -> AppSettings {
        let path: String = configFileURL.path()
        guard FileManager.default.fileExists(atPath: path) else {
            return AppSettings()
        }
        let content: String = try String(contentsOf: configFileURL, encoding: .utf8)
        return parse(content)
    }

    /// Saves settings to the TOML config file, creating the directory if needed.
    public func saveSettings(_ settings: AppSettings) async throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        let content: String = serialize(settings)
        try content.write(to: configFileURL, atomically: true, encoding: .utf8)
    }

    /// Retrieves a secret from the Keychain.
    public func getSecret(for key: SecretKey) async throws -> String? {
        try keychainStore.get(for: key)
    }

    /// Stores a secret in the Keychain.
    public func setSecret(_ value: String, for key: SecretKey) async throws {
        try keychainStore.set(value, for: key)
    }

    /// Removes a secret from the Keychain.
    public func removeSecret(for key: SecretKey) async throws {
        try keychainStore.remove(for: key)
    }

    // MARK: - TOML serialization

    /// Serializes settings to TOML format.
    private func serialize(_ settings: AppSettings) -> String {
        let lines: [String] = [
            "s3_endpoint_url = \(quoted(settings.s3EndpointURL))",
            "s3_access_key = \(quoted(settings.s3AccessKey))",
            "s3_bucket_name = \(quoted(settings.s3BucketName))",
            "s3_region = \(quoted(settings.s3Region))",
            "s3_path_prefix = \(quoted(settings.s3PathPrefix))",
            "output_mode = \(quoted(settings.outputMode.rawValue))",
            "save_folder_path = \(quoted(settings.saveFolderPath))",
            "file_retention_hours = \(settings.fileRetentionHours)",
            "launch_at_login = \(settings.launchAtLogin)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses TOML content into AppSettings, using defaults for missing keys.
    private func parse(_ content: String) -> AppSettings {
        var dict: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key: String = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
            let rawValue: String = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            dict[key] = unquote(rawValue)
        }

        let defaults: AppSettings = AppSettings()
        return AppSettings(
            s3EndpointURL: dict["s3_endpoint_url"] ?? defaults.s3EndpointURL,
            s3AccessKey: dict["s3_access_key"] ?? defaults.s3AccessKey,
            s3BucketName: dict["s3_bucket_name"] ?? defaults.s3BucketName,
            s3Region: dict["s3_region"] ?? defaults.s3Region,
            s3PathPrefix: dict["s3_path_prefix"] ?? defaults.s3PathPrefix,
            outputMode: OutputMode(rawValue: dict["output_mode"] ?? "") ?? defaults.outputMode,
            saveFolderPath: dict["save_folder_path"] ?? defaults.saveFolderPath,
            fileRetentionHours: Int(dict["file_retention_hours"] ?? "") ?? defaults.fileRetentionHours,
            launchAtLogin: dict["launch_at_login"].map { $0 == "true" } ?? defaults.launchAtLogin
        )
    }

    /// Wraps a string value in TOML double quotes, escaping inner quotes and backslashes.
    private func quoted(_ value: String) -> String {
        let escaped: String = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Strips surrounding double quotes and unescapes a TOML string value.
    private func unquote(_ value: String) -> String {
        var result: String = value
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result = String(result.dropFirst().dropLast())
            result = result
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return result
    }
}
```

### Step 4: Run tests to verify they pass

Run: `swift test --filter TOMLConfigManagerTests 2>&1 | tail -20`
Expected: All 6 tests pass.

### Step 5: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Config/ 2>&1`
Expected: No violations.

### Step 6: Commit

```bash
git add trnscrb/Infrastructure/Config/TOMLConfigManager.swift Tests/Infrastructure/TOMLConfigManagerTests.swift
git commit -m "feat(infra): add TOMLConfigManager implementing SettingsGateway"
```

---

## Task 3: AppDelegate + NSStatusItem + NSPopover

**Files:**
- Create: `trnscrb/App/AppDelegate.swift`
- Modify: `trnscrb/App/TrnscrbrApp.swift` (replace MenuBarExtra with AppDelegate adaptor)
- Create: `trnscrb/Presentation/Popover/PopoverView.swift` (placeholder shell)

**Context:** Replace the Phase 0 `MenuBarExtra` stub with the real `NSStatusItem` + `NSPopover` pattern. AppDelegate is the composition root — it creates all infrastructure instances and wires dependencies. PopoverView is a placeholder that will show "Drop files here" and a gear icon for settings. No tests for this task — it's UI wiring verified manually.

### Step 1: Create PopoverView placeholder

Create `trnscrb/Presentation/Popover/PopoverView.swift`:

```swift
import SwiftUI

/// Root view displayed inside the menu bar popover.
///
/// Shows the main content area (drop zone placeholder) with a footer
/// containing a gear icon to navigate to settings.
struct PopoverView: View {
    /// Controls whether the settings panel is visible.
    @State private var showSettings: Bool = false
    /// View model for the settings panel.
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        if showSettings {
            SettingsPanel(
                viewModel: settingsViewModel,
                onBack: { showSettings = false }
            )
        } else {
            mainContent
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Drop files here")
                .font(.headline)
                .padding(.top, 8)
            Text("or drag onto the menu bar icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .frame(width: 320, height: 360)
    }
}
```

> **Note:** `SettingsPanel` is the name for the settings view (created in Task 5). For now, create a temporary stub so it compiles. We'll replace it with the real implementation in Task 5.

Create a temporary stub — add to the bottom of `PopoverView.swift` (to be removed in Task 5):

```swift
/// Temporary stub — replaced in Task 5 with the real settings view.
private struct SettingsPanel: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onBack: () -> Void

    var body: some View {
        VStack {
            Button("Back", action: onBack)
            Text("Settings (coming in Task 5)")
        }
        .frame(width: 320, height: 360)
    }
}
```

### Step 2: Create SettingsViewModel stub

Create `trnscrb/Presentation/ViewModels/SettingsViewModel.swift` (minimal — full implementation in Task 4):

```swift
import Foundation

/// Bridges SettingsGateway to SwiftUI for the settings panel.
///
/// Loads settings and secrets, exposes them as published properties,
/// and saves changes back through the gateway.
@MainActor
public final class SettingsViewModel: ObservableObject {
    /// Current application settings.
    @Published public var settings: AppSettings = AppSettings()
    /// Mistral API key (stored in Keychain, not in AppSettings).
    @Published public var mistralAPIKey: String = ""
    /// S3 secret key (stored in Keychain, not in AppSettings).
    @Published public var s3SecretKey: String = ""

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway

    /// Creates a view model backed by the given settings gateway.
    /// - Parameter gateway: Settings persistence gateway.
    public init(gateway: any SettingsGateway) {
        self.gateway = gateway
    }

    /// Loads settings and secrets from persistent storage.
    public func load() async {
        // Full implementation in Task 4
    }

    /// Saves settings and secrets to persistent storage.
    public func save() async {
        // Full implementation in Task 4
    }
}
```

### Step 3: Create AppDelegate

Create `trnscrb/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

/// Application delegate and composition root.
///
/// Creates the `NSStatusItem` (menu bar icon), manages the `NSPopover`,
/// and wires all infrastructure dependencies. This is the only component
/// that knows about all layers — it creates concrete instances and injects
/// them into view models and use cases.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The menu bar status item showing the app icon.
    private var statusItem: NSStatusItem?
    /// The popover displayed when the status item is clicked.
    private var popover: NSPopover?
    /// Settings gateway for the lifetime of the app.
    private var settingsGateway: (any SettingsGateway)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Build infrastructure
        let keychainStore: KeychainStore = KeychainStore()
        let gateway: TOMLConfigManager = TOMLConfigManager(keychainStore: keychainStore)
        settingsGateway = gateway

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(gateway: gateway)

        // Setup popover
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(settingsViewModel: settingsVM)
        )
        self.popover = popover

        // Setup status item
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button: NSStatusBarButton = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.text",
                accessibilityDescription: "trnscrb"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem
    }

    /// Toggles the popover visibility when the menu bar icon is clicked.
    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

### Step 4: Update TrnscrbrApp.swift

Replace the contents of `trnscrb/App/TrnscrbrApp.swift`:

```swift
import SwiftUI

/// Main entry point for the trnscrb menu bar app.
///
/// The SwiftUI lifecycle manages the process. All real work is done
/// by `AppDelegate`, which is bridged via `@NSApplicationDelegateAdaptor`.
@main
struct TrnscrbrApp: App {
    /// Bridges to the AppKit AppDelegate which owns the NSStatusItem and NSPopover.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

### Step 5: Build and verify

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds with no errors.

### Step 6: Lint

Run: `swiftlint lint trnscrb/App/ trnscrb/Presentation/Popover/ trnscrb/Presentation/ViewModels/ 2>&1`
Expected: No violations (or only expected warnings — address any errors).

### Step 7: Manual verification

Run: `swift run 2>&1 &` and verify:
- [ ] No Dock icon appears
- [ ] Menu bar shows `doc.text` icon
- [ ] Clicking icon opens popover with "Drop files here" placeholder
- [ ] Clicking outside popover dismisses it
- [ ] Clicking icon again re-opens popover

Kill the process when done: `kill %1`

### Step 8: Commit

```bash
git add trnscrb/App/AppDelegate.swift trnscrb/App/TrnscrbrApp.swift trnscrb/Presentation/Popover/PopoverView.swift trnscrb/Presentation/ViewModels/SettingsViewModel.swift
git commit -m "feat(app): add AppDelegate with NSStatusItem and NSPopover shell"
```

---

## Task 4: SettingsViewModel (TDD)

**Files:**
- Modify: `trnscrb/Presentation/ViewModels/SettingsViewModel.swift` (fill in load/save)
- Create: `Tests/Presentation/SettingsViewModelTests.swift`

**Context:** SettingsViewModel is `@MainActor` and `ObservableObject`. It loads settings + secrets from `SettingsGateway`, exposes them as `@Published` properties, and saves changes back. Tests use a mock `SettingsGateway`.

### Step 1: Write failing tests

Create `Tests/Presentation/SettingsViewModelTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

/// In-memory mock for SettingsGateway used in ViewModel tests.
final class MockSettingsGateway: SettingsGateway, @unchecked Sendable {
    var settings: AppSettings = AppSettings()
    var secrets: [SecretKey: String] = [:]
    var loadCallCount: Int = 0
    var saveCallCount: Int = 0

    func loadSettings() async throws -> AppSettings {
        loadCallCount += 1
        return settings
    }

    func saveSettings(_ newSettings: AppSettings) async throws {
        saveCallCount += 1
        settings = newSettings
    }

    func getSecret(for key: SecretKey) async throws -> String? {
        secrets[key]
    }

    func setSecret(_ value: String, for key: SecretKey) async throws {
        secrets[key] = value
    }

    func removeSecret(for key: SecretKey) async throws {
        secrets[key] = nil
    }
}

@MainActor
struct SettingsViewModelTests {
    private func makeViewModel(
        settings: AppSettings = AppSettings(),
        secrets: [SecretKey: String] = [:]
    ) -> (SettingsViewModel, MockSettingsGateway) {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings = settings
        gateway.secrets = secrets
        let vm: SettingsViewModel = SettingsViewModel(gateway: gateway)
        return (vm, gateway)
    }

    // MARK: - Loading

    @Test func loadPopulatesSettingsFromGateway() async {
        let customSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://test.com",
            s3BucketName: "bucket"
        )
        let (vm, _) = makeViewModel(settings: customSettings)
        await vm.load()
        #expect(vm.settings.s3EndpointURL == "https://test.com")
        #expect(vm.settings.s3BucketName == "bucket")
    }

    @Test func loadPopulatesSecretsFromGateway() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "mk-123",
            .s3SecretKey: "sk-456"
        ]
        let (vm, _) = makeViewModel(secrets: secrets)
        await vm.load()
        #expect(vm.mistralAPIKey == "mk-123")
        #expect(vm.s3SecretKey == "sk-456")
    }

    @Test func loadWithNoSecretsLeavesEmptyStrings() async {
        let (vm, _) = makeViewModel()
        await vm.load()
        #expect(vm.mistralAPIKey == "")
        #expect(vm.s3SecretKey == "")
    }

    // MARK: - Saving

    @Test func savePersistsSettingsToGateway() async {
        let (vm, gateway) = makeViewModel()
        vm.settings.s3EndpointURL = "https://saved.com"
        vm.settings.s3BucketName = "saved-bucket"
        await vm.save()
        #expect(gateway.settings.s3EndpointURL == "https://saved.com")
        #expect(gateway.settings.s3BucketName == "saved-bucket")
    }

    @Test func savePersistsSecretsToKeychain() async {
        let (vm, gateway) = makeViewModel()
        vm.mistralAPIKey = "new-mk"
        vm.s3SecretKey = "new-sk"
        await vm.save()
        #expect(gateway.secrets[.mistralAPIKey] == "new-mk")
        #expect(gateway.secrets[.s3SecretKey] == "new-sk")
    }

    @Test func saveRemovesEmptySecrets() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "existing",
            .s3SecretKey: "existing"
        ]
        let (vm, gateway) = makeViewModel(secrets: secrets)
        await vm.load()
        vm.mistralAPIKey = ""
        vm.s3SecretKey = ""
        await vm.save()
        #expect(gateway.secrets[.mistralAPIKey] == nil)
        #expect(gateway.secrets[.s3SecretKey] == nil)
    }

    // MARK: - Round-trip

    @Test func loadThenSaveRoundTrip() async {
        let original: AppSettings = AppSettings(
            s3EndpointURL: "https://rt.com",
            outputMode: .both,
            fileRetentionHours: 48
        )
        let (vm, gateway) = makeViewModel(
            settings: original,
            secrets: [.mistralAPIKey: "rt-key"]
        )
        await vm.load()
        await vm.save()
        #expect(gateway.settings == original)
        #expect(gateway.secrets[.mistralAPIKey] == "rt-key")
    }
}
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter SettingsViewModelTests 2>&1 | tail -20`
Expected: Tests fail — `load()` and `save()` are empty stubs.

### Step 3: Implement load/save in SettingsViewModel

Update `trnscrb/Presentation/ViewModels/SettingsViewModel.swift` — fill in the `load()` and `save()` methods:

```swift
import Foundation

/// Bridges SettingsGateway to SwiftUI for the settings panel.
///
/// Loads settings and secrets, exposes them as published properties,
/// and saves changes back through the gateway.
@MainActor
public final class SettingsViewModel: ObservableObject {
    /// Current application settings.
    @Published public var settings: AppSettings = AppSettings()
    /// Mistral API key (stored in Keychain, not in AppSettings).
    @Published public var mistralAPIKey: String = ""
    /// S3 secret key (stored in Keychain, not in AppSettings).
    @Published public var s3SecretKey: String = ""
    /// Error message from the last failed operation, if any.
    @Published public var error: String?

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway

    /// Creates a view model backed by the given settings gateway.
    /// - Parameter gateway: Settings persistence gateway.
    public init(gateway: any SettingsGateway) {
        self.gateway = gateway
    }

    /// Loads settings and secrets from persistent storage.
    public func load() async {
        do {
            settings = try await gateway.loadSettings()
            mistralAPIKey = try await gateway.getSecret(for: .mistralAPIKey) ?? ""
            s3SecretKey = try await gateway.getSecret(for: .s3SecretKey) ?? ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Saves settings and secrets to persistent storage.
    public func save() async {
        do {
            try await gateway.saveSettings(settings)

            if mistralAPIKey.isEmpty {
                try await gateway.removeSecret(for: .mistralAPIKey)
            } else {
                try await gateway.setSecret(mistralAPIKey, for: .mistralAPIKey)
            }

            if s3SecretKey.isEmpty {
                try await gateway.removeSecret(for: .s3SecretKey)
            } else {
                try await gateway.setSecret(s3SecretKey, for: .s3SecretKey)
            }

            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

### Step 4: Run tests to verify they pass

Run: `swift test --filter SettingsViewModelTests 2>&1 | tail -20`
Expected: All 7 tests pass.

### Step 5: Lint

Run: `swiftlint lint trnscrb/Presentation/ViewModels/ 2>&1`
Expected: No violations.

### Step 6: Commit

```bash
git add trnscrb/Presentation/ViewModels/SettingsViewModel.swift Tests/Presentation/SettingsViewModelTests.swift
git commit -m "feat(presentation): add SettingsViewModel with load/save logic"
```

---

## Task 5: SettingsView + Final Wiring

**Files:**
- Create: `trnscrb/Presentation/Settings/SettingsView.swift`
- Modify: `trnscrb/Presentation/Popover/PopoverView.swift` (remove stub, use real SettingsView)

**Context:** Build the settings form with all fields from SPEC.md. SecureField for API keys, Picker for output mode, Toggle for launch at login. The view auto-loads settings on appear and has a Save button. Replace the SettingsPanel stub in PopoverView with the real SettingsView.

### Step 1: Create SettingsView

Create `trnscrb/Presentation/Settings/SettingsView.swift`:

```swift
import SwiftUI

/// Settings panel displayed inside the popover.
///
/// Shows all configurable fields from SPEC.md organized into sections.
/// API keys use `SecureField` and are stored in the Keychain, not the config file.
struct SettingsView: View {
    /// View model providing settings data and persistence.
    @ObservedObject var viewModel: SettingsViewModel
    /// Called when the user taps the back button.
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settingsForm
        }
        .frame(width: 320, height: 480)
        .task { await viewModel.load() }
    }

    /// Navigation header with back button and save button.
    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text("Settings")
                .font(.headline)
            Spacer()
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Button("Save") {
                Task { await viewModel.save() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Form containing all settings sections.
    private var settingsForm: some View {
        Form {
            s3Section
            mistralSection
            outputSection
            generalSection
        }
        .formStyle(.grouped)
    }

    /// S3 Storage configuration fields.
    private var s3Section: some View {
        Section("S3 Storage") {
            TextField("Endpoint URL", text: $viewModel.settings.s3EndpointURL)
                .textFieldStyle(.roundedBorder)
            TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret Key", text: $viewModel.s3SecretKey)
                .textFieldStyle(.roundedBorder)
            TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                .textFieldStyle(.roundedBorder)
            TextField("Region", text: $viewModel.settings.s3Region)
                .textFieldStyle(.roundedBorder)
            TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Mistral API key field.
    private var mistralSection: some View {
        Section("Mistral API") {
            SecureField("API Key", text: $viewModel.mistralAPIKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Output mode and save folder configuration.
    private var outputSection: some View {
        Section("Output") {
            Picker("Mode", selection: $viewModel.settings.outputMode) {
                Text("Clipboard").tag(OutputMode.clipboard)
                Text("Save to Folder").tag(OutputMode.saveToFolder)
                Text("Both").tag(OutputMode.both)
            }
            if viewModel.settings.outputMode != .clipboard {
                TextField("Save Folder", text: $viewModel.settings.saveFolderPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// General settings: retention and launch at login.
    private var generalSection: some View {
        Section("General") {
            HStack {
                Text("File Retention")
                Spacer()
                TextField(
                    "Hours",
                    value: $viewModel.settings.fileRetentionHours,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("hours")
                    .foregroundStyle(.secondary)
            }
            Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
        }
    }
}
```

### Step 2: Update PopoverView — remove stub, use SettingsView

Replace the `SettingsPanel` stub and update `PopoverView` in `trnscrb/Presentation/Popover/PopoverView.swift`:

```swift
import SwiftUI

/// Root view displayed inside the menu bar popover.
///
/// Shows the main content area (drop zone placeholder) with a footer
/// containing a gear icon to navigate to settings.
struct PopoverView: View {
    /// Controls whether the settings panel is visible.
    @State private var showSettings: Bool = false
    /// View model for the settings panel.
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        if showSettings {
            SettingsView(
                viewModel: settingsViewModel,
                onBack: { showSettings = false }
            )
        } else {
            mainContent
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Drop files here")
                .font(.headline)
                .padding(.top, 8)
            Text("or drag onto the menu bar icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .frame(width: 320, height: 360)
    }
}
```

### Step 3: Build

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds.

### Step 4: Lint

Run: `swiftlint lint trnscrb/Presentation/ 2>&1`
Expected: No violations.

### Step 5: Manual verification

Run: `swift run 2>&1 &` and verify:
- [ ] Popover shows "Drop files here" with gear icon
- [ ] Clicking gear shows settings form with all sections
- [ ] SecureField shows dots for API keys
- [ ] Output mode picker works (Clipboard / Save to Folder / Both)
- [ ] Save folder field appears only when mode is not "Clipboard"
- [ ] Back button returns to main view
- [ ] Save button persists — kill and relaunch, verify values are preserved
- [ ] Config file created at `~/.config/trnscrb/config.toml`
- [ ] API keys NOT in the config file (only in Keychain)

Kill the process when done: `kill %1`

### Step 6: Commit

```bash
git add trnscrb/Presentation/Settings/SettingsView.swift trnscrb/Presentation/Popover/PopoverView.swift
git commit -m "feat(presentation): add SettingsView with full settings form"
```

---

## Summary

| Task | Component | Tests | Files |
|------|-----------|-------|-------|
| 1 | KeychainStore | 5 | 2 new |
| 2 | TOMLConfigManager | 6 | 2 new |
| 3 | AppDelegate + PopoverView | manual | 3 new, 1 modified |
| 4 | SettingsViewModel | 7 | 1 modified, 1 new |
| 5 | SettingsView + wiring | manual | 1 new, 1 modified |

**Total:** 18 new tests, 8 new files, 2 modified files. No external dependencies.

**After Phase 1:** The app launches as a menu bar icon, opens a popover, navigates to settings, persists config to TOML + secrets to Keychain. Ready for Phase 2 (pipeline components) which needs these stored credentials.
