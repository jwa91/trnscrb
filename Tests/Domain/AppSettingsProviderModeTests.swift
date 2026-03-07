import Testing

@testable import trnscrb

struct AppSettingsProviderModeTests {
    @Test func defaultsUseLocalAppleForAllMedia() {
        let settings: AppSettings = AppSettings()

        #expect(settings.audioProviderMode == .localApple)
        #expect(settings.pdfProviderMode == .localApple)
        #expect(settings.imageProviderMode == .localApple)
    }

    @Test func modeForFileTypeReturnsPerMediaValue() {
        let settings: AppSettings = AppSettings(
            audioProviderMode: .localApple,
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )

        #expect(settings.mode(for: .audio) == .localApple)
        #expect(settings.mode(for: .pdf) == .mistral)
        #expect(settings.mode(for: .image) == .localApple)
    }

    @Test func requiresCloudCredentialsWhenAnyMediaUsesMistral() {
        let settings: AppSettings = AppSettings(
            audioProviderMode: .localApple,
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )

        #expect(settings.requiresCloudCredentials)
    }

    @Test func doesNotRequireCloudCredentialsWhenAllMediaAreLocal() {
        let settings: AppSettings = AppSettings(
            audioProviderMode: .localApple,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(!settings.requiresCloudCredentials)
    }

    // MARK: - Bucket mirroring

    @Test func bucketMirroringDefaultsToDisabled() {
        let settings: AppSettings = AppSettings()

        #expect(!settings.bucketMirroringEnabled)
    }

    @Test func requiresS3CredentialsWhenMirroringEnabledWithAllLocalProviders() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: true,
            audioProviderMode: .localApple,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(settings.requiresS3Credentials)
    }

    @Test func doesNotRequireS3CredentialsWhenCloudActiveAndMirroringDisabled() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: false,
            audioProviderMode: .mistral,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(!settings.requiresS3Credentials)
    }

    @Test func doesNotRequireS3CredentialsWhenAllLocalAndMirroringDisabled() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: false,
            audioProviderMode: .localApple,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(!settings.requiresS3Credentials)
    }

    @Test func pipelineSummaryUsesCloudProcessingMirroringOffAndSaveFolder() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: false,
            saveFolderPath: "~/Documents/trnscrb",
            audioProviderMode: .mistral,
            pdfProviderMode: .mistral,
            imageProviderMode: .mistral
        )

        #expect(settings.pipelineSummary == "Cloud processing • S3 mirroring off • Save to ~/Documents/trnscrb")
    }

    @Test func pipelineSummaryUsesLocalProcessingMirroringOnAndSaveFolder() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: true,
            saveFolderPath: "/tmp/notes",
            audioProviderMode: .localApple,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(settings.pipelineSummary == "Local processing • S3 mirroring on • Save to /tmp/notes")
    }

    @Test func pipelineSummaryUsesMixedProcessingWhenModesDiffer() {
        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: true,
            saveFolderPath: "~/Documents/trnscrb",
            audioProviderMode: .mistral,
            pdfProviderMode: .localApple,
            imageProviderMode: .localApple
        )

        #expect(settings.pipelineSummary == "Mixed processing • S3 mirroring on • Save to ~/Documents/trnscrb")
    }
}
