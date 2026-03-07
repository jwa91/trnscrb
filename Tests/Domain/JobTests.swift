import Foundation
import Testing

@testable import trnscrb

private func makeJob(
    fileURL: URL = URL(filePath: "/tmp/recording.mp3")
) -> Job {
    Job(
        fileType: .audio,
        fileURL: fileURL
    )
}

struct JobStatusTests {
    @Test func initialStatusIsPending() {
        let job: Job = makeJob()
        #expect(job.status == .pending)
        #expect(job.markdown == nil)
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings.isEmpty)
        #expect(job.completedAt == nil)
    }

    @Test func fileNameDerivedFromURL() {
        let job: Job = makeJob(fileURL: URL(filePath: "/tmp/meeting-notes.mp3"))
        #expect(job.fileName == "meeting-notes.mp3")
    }
}

struct JobStateTransitionTests {
    // MARK: - Happy path: pending -> uploading -> processing -> completed

    @Test func pendingToUploading() {
        var job: Job = makeJob()
        job.startUpload()
        #expect(job.status == .uploading(progress: 0))
    }

    @Test func uploadProgress() {
        var job: Job = makeJob()
        job.startUpload()
        job.updateUploadProgress(0.5)
        #expect(job.status == .uploading(progress: 0.5))
    }

    @Test func uploadProgressClampsTo0And1() {
        var job: Job = makeJob()
        job.startUpload()
        job.updateUploadProgress(-0.5)
        #expect(job.status == .uploading(progress: 0))
        job.updateUploadProgress(1.5)
        #expect(job.status == .uploading(progress: 1))
    }

    @Test func uploadingToProcessing() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        #expect(job.status == .processing)
    }

    @Test func processingToCompleted() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Hello")
        #expect(job.status == .completed)
        #expect(job.markdown == "# Hello")
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings.isEmpty)
        #expect(job.completedAt != nil)
    }

    @Test func processingToCompletedWithWarnings() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(
            markdown: "# Hello",
            mirrorWarnings: ["Processed file successfully, but mirroring to S3 failed: S3 secret key not configured"],
            deliveryWarnings: ["Copied markdown to the clipboard, but saving the file failed."]
        )
        #expect(job.status == .completed)
        #expect(job.markdown == "# Hello")
        #expect(job.mirrorWarnings == [
            "Processed file successfully, but mirroring to S3 failed: S3 secret key not configured"
        ])
        #expect(job.deliveryWarnings == ["Copied markdown to the clipboard, but saving the file failed."])
        #expect(
            job.warningMessage
                == "Processed file successfully, but mirroring to S3 failed: S3 secret key not configured Copied markdown to the clipboard, but saving the file failed."
        )
    }

    @Test func processingToCompletedStoresDeliveryMetadata() {
        let savedFileURL: URL = URL(filePath: "/tmp/meeting.md")
        let presignedSourceURL: URL = URL(string: "https://s3.example.com/presigned")!
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(
            markdown: "# Hello",
            savedFileURL: savedFileURL,
            presignedSourceURL: presignedSourceURL
        )

        #expect(job.savedFileURL == savedFileURL)
        #expect(job.presignedSourceURL == presignedSourceURL)
    }

    // MARK: - Failure transitions

    @Test func pendingToFailed() {
        var job: Job = makeJob()
        job.fail(error: "Network offline")
        #expect(job.status == .failed(error: "Network offline"))
        #expect(job.completedAt != nil)
    }

    @Test func uploadingToFailed() {
        var job: Job = makeJob()
        job.startUpload()
        job.fail(error: "S3 upload failed")
        #expect(job.status == .failed(error: "S3 upload failed"))
    }

    @Test func processingToFailed() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.fail(error: "API error")
        #expect(job.status == .failed(error: "API error"))
    }

    // MARK: - Invalid transitions (no-ops)

    @Test func cannotSkipUploadingState() {
        var job: Job = makeJob()
        job.startProcessing()  // invalid: must upload first
        #expect(job.status == .pending)
    }

    @Test func cannotCompleteFromUploading() {
        var job: Job = makeJob()
        job.startUpload()
        job.complete(markdown: "nope")  // invalid: must process first
        #expect(job.status == .uploading(progress: 0))
        #expect(job.markdown == nil)
    }

    @Test func cannotFailFromCompleted() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Done")
        job.fail(error: "too late")  // invalid: already completed
        #expect(job.status == .completed)
    }

    @Test func cannotFailFromAlreadyFailed() {
        var job: Job = makeJob()
        job.fail(error: "first error")
        job.fail(error: "second error")  // invalid: already failed
        #expect(job.status == .failed(error: "first error"))
    }

    @Test func requeueResetsFailedJobToPending() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.fail(error: "offline")

        job.requeue()

        #expect(job.status == .pending)
        #expect(job.markdown == nil)
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings.isEmpty)
        #expect(job.savedFileURL == nil)
        #expect(job.presignedSourceURL == nil)
        #expect(job.completedAt == nil)
    }

    @Test func completedJobDoesNotRequeue() {
        let savedFileURL: URL = URL(filePath: "/tmp/out.md")
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(
            markdown: "# Done",
            deliveryWarnings: ["warning"],
            savedFileURL: savedFileURL,
            presignedSourceURL: URL(string: "https://s3.example.com/source")!
        )

        job.requeue()

        #expect(job.status == .completed)
        #expect(job.markdown == "# Done")
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings == ["warning"])
        #expect(job.savedFileURL == savedFileURL)
        #expect(job.completedAt != nil)
    }
}

struct JobIdentityTests {
    @Test func uniqueIds() {
        let job1: Job = makeJob(fileURL: URL(filePath: "/tmp/a.mp3"))
        let job2: Job = makeJob(fileURL: URL(filePath: "/tmp/a.mp3"))
        #expect(job1.id != job2.id)
    }
}
