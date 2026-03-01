import Foundation
import Testing

@testable import trnscrb

struct JobStatusTests {
    @Test func initialStatusIsPending() {
        let job: Job = Job(
            fileName: "test.mp3",
            fileType: .audio,
            fileURL: URL(filePath: "/tmp/test.mp3")
        )
        #expect(job.status == .pending)
        #expect(job.markdown == nil)
        #expect(job.completedAt == nil)
    }
}

struct JobStateTransitionTests {
    private func makeJob() -> Job {
        Job(
            fileName: "recording.mp3",
            fileType: .audio,
            fileURL: URL(filePath: "/tmp/recording.mp3")
        )
    }

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
        #expect(job.completedAt != nil)
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
}

struct JobIdentityTests {
    @Test func uniqueIds() {
        let job1: Job = Job(
            fileName: "a.mp3", fileType: .audio, fileURL: URL(filePath: "/tmp/a.mp3"))
        let job2: Job = Job(
            fileName: "a.mp3", fileType: .audio, fileURL: URL(filePath: "/tmp/a.mp3"))
        #expect(job1.id != job2.id)
    }
}
