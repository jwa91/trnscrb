import Foundation
import Testing

@testable import trnscrb

private func makePresentationJob(
    fileType: FileType = .audio,
    fileName: String = "recording.mp3"
) -> Job {
    Job(
        fileType: fileType,
        fileURL: URL(filePath: "/tmp/\(fileName)")
    )
}

struct JobRowPresentationTests {
    @Test func mapsFileTypesToBadgeStyles() {
        let audio: JobRowPresentation = JobRowPresentation(job: makePresentationJob(fileType: .audio))
        let pdf: JobRowPresentation = JobRowPresentation(
            job: makePresentationJob(fileType: .pdf, fileName: "document.pdf")
        )
        let image: JobRowPresentation = JobRowPresentation(
            job: makePresentationJob(fileType: .image, fileName: "photo.png")
        )

        #expect(audio.badgeSymbolName == "waveform")
        #expect(audio.badgeTint == .orange)
        #expect(pdf.badgeSymbolName == "doc.richtext")
        #expect(pdf.badgeTint == .red)
        #expect(image.badgeSymbolName == "photo")
        #expect(image.badgeTint == .blue)
    }

    @Test func failureSubtitleOverridesMetadata() {
        var job: Job = makePresentationJob()
        job.fail(error: "S3 upload failed")

        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        #expect(presentation.subtitleKind == .error)
        #expect(presentation.subtitleText == "S3 upload failed")
        #expect(!presentation.showsMarkdownAction)
        #expect(!presentation.showsSourceLinkAction)
    }

    @Test func warningSubtitleOverridesCompletionMetadata() {
        var job: Job = makePresentationJob()
        job.startUpload()
        job.startProcessing()
        job.complete(
            markdown: "# Notes",
            deliveryWarnings: ["Copied markdown, but saving failed."]
        )

        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        #expect(presentation.subtitleKind == .warning)
        #expect(presentation.subtitleText == "Copied markdown, but saving failed.")
        #expect(presentation.showsMarkdownAction)
        #expect(!presentation.showsSourceLinkAction)
    }

    @Test func completedJobsUseCompletionMetadataAndExposeActions() {
        let sourceURL: URL = URL(string: "https://s3.example.com/source")!
        var job: Job = makePresentationJob()
        job.startUpload()
        job.startProcessing()
        job.complete(
            markdown: "# Transcript",
            presignedSourceURL: sourceURL
        )

        let presentation: JobRowPresentation = JobRowPresentation(
            job: job,
            now: job.completedAt ?? Date()
        )

        #expect(presentation.subtitleKind == .metadata)
        #expect(presentation.subtitleText == "Audio • now")
        #expect(presentation.showsCompletionActions)
        #expect(!presentation.showsPassiveCompletionState)
        #expect(presentation.showsMarkdownAction)
        #expect(presentation.showsSourceLinkAction)
    }

    @Test func completedLocalJobsStillShowVisibleActionsWithoutPassiveStatusFallback() {
        var job: Job = makePresentationJob()
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Transcript")

        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        #expect(presentation.showsCompletionActions)
        #expect(!presentation.showsPassiveCompletionState)
        #expect(presentation.showsMarkdownAction)
        #expect(!presentation.showsSourceLinkAction)
    }

    @Test func completedUploadShowsFinalizingInsteadOfStuck100Percent() {
        var job: Job = makePresentationJob()
        job.startUpload()
        job.updateUploadProgress(1)

        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        #expect(presentation.subtitleKind == .metadata)
        #expect(presentation.subtitleText == "Audio • Finalizing upload")
        #expect(presentation.uploadActivity == .finalizing)
    }

    @Test func nearCompleteUploadClampsDisplayedPercentBelow100() {
        var job: Job = makePresentationJob()
        job.startUpload()
        job.updateUploadProgress(0.996)

        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        #expect(presentation.subtitleText == "Audio • Uploading 99%")
        #expect(presentation.uploadActivity == .progress(percent: 99, value: 0.996))
    }
}
