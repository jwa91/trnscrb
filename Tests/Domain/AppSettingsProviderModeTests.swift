import Testing

@testable import trnscrb

struct AppSettingsProviderModeTests {
    @Test func defaultsUseMistralForAllMedia() {
        let settings: AppSettings = AppSettings()

        #expect(settings.audioProviderMode == .mistral)
        #expect(settings.pdfProviderMode == .mistral)
        #expect(settings.imageProviderMode == .mistral)
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
}
