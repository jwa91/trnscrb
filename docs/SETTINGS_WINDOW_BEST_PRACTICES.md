# Settings Window Best Practices — macOS + Liquid Glass

Best practices for building a Settings window in a macOS app targeting macOS Tahoe (26) with the Liquid Glass design language.

---

## 1. Use the SwiftUI `Settings` Scene

- Declare a `Settings` scene in your `App` struct — this is the standard way to present preferences on macOS.
- The system automatically wires up **Cmd+,**, the app menu item, and window lifecycle.

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        Settings { SettingsView() }
    }
}
```

## 2. Navigation Pattern: Choose by Complexity

| Complexity | Pattern | When to Use |
|---|---|---|
| **Few panes (2–5)** | `TabView` with toolbar-style tabs | Simple apps with a handful of categories |
| **Many panes (6+)** | `NavigationSplitView` with sidebar | Complex apps mirroring System Settings style |
| **Single pane** | Plain `Form` | Very simple apps with < 10 settings |

### TabView approach
```swift
TabView {
    GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gear") }
    AppearanceSettingsView()
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
}
```

### Sidebar approach (System Settings style)
```swift
NavigationSplitView {
    List(selection: $selectedPane) { ... }
        .toolbar(removing: .sidebarToggle)
} detail: {
    selectedPane.view
}
```

## 3. "General" Tab Always Comes First

- The first tab/pane should be **General** — this is the macOS convention.
- Place the most frequently changed settings there.
- Order remaining tabs from most-used to least-used.

## 4. Window Title Reflects the Active Pane

- Update the window title to match the currently selected settings pane.
- For `TabView`, SwiftUI handles this automatically.
- For sidebar navigation, set `.navigationTitle()` on each detail view.

## 5. Group Controls with `GroupBox` and `Form`

- Use `Form` as the root container inside each settings pane for proper label alignment.
- Use `.formStyle(.grouped)` for the System Settings look with inset grouped rows.
- Wrap logically related controls in `GroupBox` with a label.

```swift
Form {
    GroupBox("Transcription") {
        Picker("Language", selection: $language) { ... }
        Toggle("Auto-detect language", isOn: $autoDetect)
    }
    GroupBox("Output") {
        Picker("Format", selection: $format) { ... }
        Toggle("Include timestamps", isOn: $timestamps)
    }
}
.formStyle(.grouped)
```

## 6. Fixed Window Size per Pane

- Each settings pane should have a fixed, appropriate size — avoid making settings windows resizable.
- Use `.frame(width:height:)` to set dimensions per pane.
- When switching tabs, the window should resize to fit the new pane's content.
- Typical width: **450–550pt**. Height varies by content.

## 7. Liquid Glass: Navigation Layer Only

Glass effects apply automatically to navigation chrome (toolbar, tabs). Do **not** add glass to:

- Form controls or GroupBox containers
- Content areas, lists of settings, or labels
- Toggle/Picker/TextField controls

**Do:**
- Let the toolbar and tab bar adopt Liquid Glass automatically (they do when compiled for macOS Tahoe)
- Use `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)` only for floating action buttons, not inline form controls

**Don't:**
- Apply `.glassEffect()` to GroupBox, Form, or Section containers
- Stack glass-on-glass (e.g., glass toolbar with glass sub-toolbar)
- Apply glass to content that scrolls beneath navigation

## 8. Use Standard Controls

- **Toggle** for on/off settings
- **Picker** (`.pickerStyle(.menu)`) for choosing from a list — this is the macOS default
- **Picker** (`.pickerStyle(.segmented)`) only for 2–4 mutually exclusive options that benefit from visibility
- **TextField** for text input with `.textFieldStyle(.roundedBorder)`
- **Stepper** or **Slider** for numeric values
- **KeyboardShortcut** fields for hotkey assignment

Avoid custom controls when a system control exists — standard controls automatically adopt Liquid Glass styling and respect accessibility settings.

## 9. Persist with `@AppStorage`

- Use `@AppStorage` for simple preferences that map to `UserDefaults`.
- Name keys with reverse-DNS or descriptive strings: `@AppStorage("outputFormat")`.
- For complex settings, use a dedicated settings model with `Codable` + `UserDefaults`.

## 10. Label Alignment and Spacing

- `Form` on macOS automatically right-aligns labels — don't fight this convention.
- Use the 8pt spacing grid: 8, 12, 16, 20, 24pt between groups.
- External spacing (between GroupBoxes) should be ≥ internal spacing (within a GroupBox).
- Section headers use `.font(.headline)`.

## 11. Accessibility

- All controls must have minimum **44pt hit targets** (width and height).
- System controls handle this by default — only verify custom controls.
- Liquid Glass automatically adapts to Reduce Transparency, Increase Contrast, and Reduce Motion.
- Use semantic colors (`.primary`, `.secondary`) not hardcoded colors.
- Ensure all controls have accessible labels (implicit from `Label` or explicit `.accessibilityLabel()`).

## 12. Keyboard Navigation

- `Cmd+,` must open Settings (automatic with `Settings` scene).
- `Tab` key should cycle through controls in logical reading order.
- `Esc` should close the Settings window.
- If using tabs, don't override `Cmd+1/2/3...` — let the system handle tab switching.

## 13. Instant Apply (No Save Button)

- macOS convention: settings take effect **immediately** — there is no "Save" or "Apply" button.
- Use `onChange(of:)` or bindings to apply changes in real time.
- If a setting requires a restart, show an inline note: *"Restart required to take effect."*
- For destructive or irreversible settings, use a confirmation dialog.

## 14. Visual Hierarchy with SF Symbols

- Use SF Symbols in tab items and section headers.
- Apply `.symbolRenderingMode(.hierarchical)` for depth.
- Match symbol weight to adjacent text weight.
- Use tinted icon backgrounds (15% opacity) for tab icons if using sidebar navigation:

```swift
ZStack {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.blue.opacity(0.15))
        .frame(width: 28, height: 28)
    Image(systemName: "gear")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.blue)
}
```

## 15. Typography

| Element | Style |
|---|---|
| Pane/section title | `.font(.headline).fontWeight(.semibold)` |
| Control label | `.font(.body)` (default) |
| Description/help text | `.font(.caption).foregroundStyle(.secondary)` |
| Inline warning | `.font(.caption).foregroundStyle(.orange)` |

Minimum text size: **11pt**. Never use Ultralight or Thin weights.

## 16. Settings Window Should Not Have a Toolbar Title on Tabs

- When using `TabView`, the toolbar displays tab icons — **do not** add a redundant toolbar title.
- When using sidebar navigation, show the pane name as the navigation title in the detail area.

## 17. Help Text and Descriptions

- Place help text below controls using `.font(.caption).foregroundStyle(.secondary)`.
- Keep descriptions to one line when possible.
- For complex settings, link to documentation or use a popover (info button `"info.circle"`).
- Don't use tooltips as the only explanation — they're not discoverable.

## 18. Animations Between Panes

- When switching panes, the window should resize smoothly with animation.
- SwiftUI `TabView` handles this automatically.
- For custom navigation, use `.animation(.easeInOut(duration: 0.2))` on the window frame change.
- Content within panes should not animate on appear — settings should feel stable and immediate.

---

## Quick Checklist

- [ ] Uses `Settings` scene (Cmd+, works)
- [ ] General tab is first
- [ ] Window title matches active pane
- [ ] Controls use `Form` + `.formStyle(.grouped)`
- [ ] Related controls grouped in `GroupBox`
- [ ] No glass on content — only on navigation chrome
- [ ] Standard controls used (Toggle, Picker, TextField)
- [ ] Settings apply instantly (no Save button)
- [ ] `@AppStorage` for persistence
- [ ] 44pt minimum hit targets
- [ ] Proper label alignment (right-aligned by Form)
- [ ] Keyboard navigation works (Tab, Esc, Cmd+,)
- [ ] Help text in `.caption` + `.secondary`
- [ ] Fixed window size per pane

---

## Sources

- [Apple HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Apple HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/)
- [SwiftUI Settings Scene](https://developer.apple.com/documentation/swiftui/settings)
- [WWDC25 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Liquid Glass Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [Adopting Liquid Glass — LogRocket](https://blog.logrocket.com/ux-design/adopting-liquid-glass-examples-best-practices/)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
