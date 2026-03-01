# trnscrb — Architecture

> Clean Architecture applied to a Swift macOS menu bar app.

![Architecture diagram](architecture-v0-1.png)

## Layers

Dependencies always point inward — outer layers depend on inner layers, never the reverse.

```mermaid
graph TB
    subgraph Domain["Domain — pure Swift, no framework imports"]
        Entities["Entities<br/><i>Job, FileType, TranscriptionResult</i>"]
        UseCases["Use Cases<br/><i>ProcessFile, CleanupRetention</i>"]
        Gateways["Gateway Protocols<br/><i>StorageGateway, TranscriptionGateway,<br/>DeliveryGateway, SettingsGateway</i>"]
    end

    subgraph Adapters["Interface Adapters — ViewModels"]
        JobListVM["JobListViewModel"]
        SettingsVM["SettingsViewModel"]
    end

    subgraph Presentation["Presentation — SwiftUI"]
        PopoverView
        DropZoneView
        SettingsView
        JobListView
    end

    subgraph Infrastructure["Infrastructure — URLSession, Keychain, FS"]
        S3Client
        MistralAudioProvider
        MistralOCRProvider
        KeychainStore
        TOMLConfig
        ClipboardDelivery
        FileDelivery
    end

    subgraph App["Composition Root"]
        AppDelegate["AppDelegate<br/><i>NSStatusItem, NSPopover, DI wiring</i>"]
    end

    Adapters -->|depends on| Domain
    Presentation -->|binds to| Adapters
    Infrastructure -->|implements| Gateways
    App -->|wires| Domain
    App -->|wires| Adapters
    App -->|wires| Infrastructure
    App -->|wires| Presentation

    style Domain fill:#d3f9d8,stroke:#22c55e
    style Adapters fill:#e5dbff,stroke:#8b5cf6
    style Presentation fill:#dbe4ff,stroke:#4a9eed
    style Infrastructure fill:#fff3bf,stroke:#f59e0b
    style App fill:#fff3bf,stroke:#92400e
```

## Data Flow

The core pipeline for every file drop:

```mermaid
sequenceDiagram
    participant U as User
    participant A as AppDelegate
    participant J as JobQueue
    participant S as S3Client
    participant M as Mistral API
    participant D as Delivery

    U->>A: Drop file on menu bar icon
    A->>J: Create Job (validate file type)
    J->>S: Upload file to S3 bucket
    S-->>J: Presigned URL
    J->>M: POST presigned URL
    Note over M: Voxtral (audio)<br/>OCR 3 (PDF/image)
    M-->>J: Markdown result
    J->>D: Deliver markdown
    D-->>U: Clipboard copy / .md file save
    D-->>U: macOS notification
```

## Folder Structure

```
trnscrb/
├── App/                          # Composition root
│   ├── trnscrb.swift             # @main entry point
│   └── AppDelegate.swift         # NSStatusItem, NSPopover, DI wiring
├── Domain/                       # Pure Swift — no framework imports
│   ├── Entities/
│   │   ├── Job.swift             # State machine: uploading → processing → done/error
│   │   ├── FileType.swift        # Audio/PDF/image routing + extension sets
│   │   └── TranscriptionResult.swift
│   ├── UseCases/
│   │   ├── ProcessFileUseCase.swift
│   │   └── CleanupRetentionUseCase.swift
│   └── Gateways/                 # Protocols only — owned by domain
│       ├── StorageGateway.swift
│       ├── TranscriptionGateway.swift
│       ├── DeliveryGateway.swift
│       └── SettingsGateway.swift
├── Infrastructure/               # Implements gateway protocols
│   ├── Storage/
│   │   └── S3Client.swift
│   ├── Transcription/
│   │   ├── MistralAudioProvider.swift
│   │   └── MistralOCRProvider.swift
│   ├── Delivery/
│   │   ├── ClipboardDelivery.swift
│   │   └── FileDelivery.swift
│   ├── Keychain/
│   │   └── KeychainStore.swift
│   └── Config/
│       └── TOMLConfigManager.swift
└── Presentation/                 # SwiftUI views + ViewModels
    ├── ViewModels/
    │   ├── JobListViewModel.swift
    │   └── SettingsViewModel.swift
    ├── Popover/
    │   ├── PopoverView.swift
    │   ├── DropZoneView.swift
    │   └── JobListView.swift
    └── Settings/
        └── SettingsView.swift
```

## Key Design Decisions

**Gateway protocols are owned by the domain.** `StorageGateway`, `TranscriptionGateway`, etc. are defined in `Domain/Gateways/`. Infrastructure code imports and conforms to them. This is the dependency inversion that makes the architecture work — the domain never knows about S3, Mistral, or the file system.

**Views are humble objects.** SwiftUI views bind to ViewModels via `@ObservedObject` / `@StateObject` and contain no business logic. This keeps the presentation layer thin and testable through the ViewModels.

**AppDelegate is the only component that knows everything.** It creates concrete infrastructure instances, injects them into use cases, and wires ViewModels to views. No other layer has this cross-cutting knowledge.

**TranscriptionGateway unifies audio and OCR.** Both `MistralAudioProvider` and `MistralOCRProvider` conform to the same protocol, so the `ProcessFileUseCase` routes by `FileType` without knowing which API is called.

**Single Mistral API key covers all processing.** The settings layer stores one key in Keychain. Both providers receive it through dependency injection — no key management logic in the domain.
