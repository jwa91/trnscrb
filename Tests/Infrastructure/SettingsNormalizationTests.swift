import Foundation
import Testing

@testable import trnscrb

struct SettingsNormalizationTests {
    @Test func normalizedForUseTrimsCredentialsAndSaveFolder() {
        let input: AppSettings = AppSettings(
            s3EndpointURL: "  s3.example.com  ",
            s3AccessKey: "  AKID  ",
            s3BucketName: "  bucket  ",
            s3Region: "  eu-west  ",
            s3PathPrefix: "  uploads  ",
            saveFolderPath: "  ~/Documents/trnscrb  ",
            outputFileNamePrefix: "  notes-  ",
            outputFileNameTemplate: "  {prefix}{fileType}  ",
            appleAudioLocaleIdentifier: "  nl-NL  "
        )

        let normalized: AppSettings = input.normalizedForUse

        #expect(normalized.s3EndpointURL == "https://s3.example.com")
        #expect(normalized.s3AccessKey == "AKID")
        #expect(normalized.s3BucketName == "bucket")
        #expect(normalized.s3Region == "eu-west")
        #expect(normalized.s3PathPrefix == "uploads/")
        #expect(normalized.saveFolderPath == "~/Documents/trnscrb")
        #expect(normalized.outputFileNamePrefix == "notes-")
        #expect(normalized.outputFileNameTemplate == "{prefix}{fileType}")
        #expect(normalized.appleAudioLocaleIdentifier == "nl-NL")
    }

    @Test func normalizedEndpointPreservesExplicitScheme() {
        #expect("http://localhost:9000".normalizedEndpointURLString == "http://localhost:9000")
        #expect("https://s3.example.com".normalizedEndpointURLString == "https://s3.example.com")
    }

    @Test func trimmedPathPrefixAddsAtMostOneTrailingSlash() {
        #expect("uploads".trimmedPathPrefix == "uploads/")
        #expect("uploads/".trimmedPathPrefix == "uploads/")
        #expect("   ".trimmedPathPrefix == "")
    }

    @Test func blankAppleAudioLocaleFallsBackToDefault() {
        let input: AppSettings = AppSettings(
            appleAudioLocaleIdentifier: "   "
        )

        let normalized: AppSettings = input.normalizedForUse

        #expect(
            normalized.appleAudioLocaleIdentifier == AppSettings.defaultAppleAudioLocaleIdentifier
        )
    }
}
