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
    // MARK: - Happy path: pending -> processing -> mirroring? -> delivering -> completed

    @Test func pendingToProcessing() {
        var job: Job = makeJob()
        job.startProcessing()
        #expect(job.status == .processing)
    }

    @Test func processingToMirroring() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startMirroring()
        #expect(job.status == .mirroring(progress: 0))
    }

    @Test func mirroringProgress() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startMirroring()
        job.updateMirroringProgress(0.5)
        #expect(job.status == .mirroring(progress: 0.5))
    }

    @Test func mirroringProgressClampsTo0And1() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startMirroring()
        job.updateMirroringProgress(-0.5)
        #expect(job.status == .mirroring(progress: 0))
        job.updateMirroringProgress(1.5)
        #expect(job.status == .mirroring(progress: 1))
    }

    @Test func processingToDelivering() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
        #expect(job.status == .delivering)
    }

    @Test func deliveringToCompleted() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
        job.complete(markdown: "# Hello")
        #expect(job.status == .completed)
        #expect(job.markdown == "# Hello")
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings.isEmpty)
        #expect(job.completedAt != nil)
    }

    @Test func deliveringToCompletedWithWarnings() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
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

    @Test func deliveringToCompletedStoresDeliveryMetadata() {
        let savedFileURL: URL = URL(filePath: "/tmp/meeting.md")
        let remoteSourceURL: URL = URL(string: "https://s3.example.com/presigned")!
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
        job.complete(
            markdown: "# Hello",
            savedFileURL: savedFileURL,
            remoteSourceURL: remoteSourceURL
        )

        #expect(job.savedFileURL == savedFileURL)
        #expect(job.remoteSourceURL == remoteSourceURL)
    }

    // MARK: - Failure transitions

    @Test func pendingToFailed() {
        var job: Job = makeJob()
        job.fail(error: "Network offline")
        #expect(job.status == .failed(error: "Network offline"))
        #expect(job.completedAt != nil)
    }

    @Test func mirroringToFailed() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startMirroring()
        job.fail(error: "S3 mirroring failed")
        #expect(job.status == .failed(error: "S3 mirroring failed"))
    }

    @Test func processingToFailed() {
        var job: Job = makeJob()
        job.startProcessing()
        job.fail(error: "API error")
        #expect(job.status == .failed(error: "API error"))
    }

    @Test func deliveringToFailed() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
        job.fail(error: "Write failed")
        #expect(job.status == .failed(error: "Write failed"))
    }

    // MARK: - Invalid transitions (no-ops)

    @Test func cannotSkipProcessingState() {
        var job: Job = makeJob()
        job.startMirroring()  // invalid: must process first
        #expect(job.status == .pending)
    }

    @Test func cannotStartDeliveryFromPending() {
        var job: Job = makeJob()
        job.startDelivery()
        #expect(job.status == .pending)
    }

    @Test func cannotCompleteFromProcessing() {
        var job: Job = makeJob()
        job.startProcessing()
        job.complete(markdown: "nope")  // invalid: must deliver first
        #expect(job.status == .processing)
        #expect(job.markdown == nil)
    }

    @Test func cannotFailFromCompleted() {
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
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
        job.startProcessing()
        job.startDelivery()
        job.fail(error: "offline")

        job.requeue()

        #expect(job.status == .pending)
        #expect(job.markdown == nil)
        #expect(job.mirrorWarnings.isEmpty)
        #expect(job.deliveryWarnings.isEmpty)
        #expect(job.savedFileURL == nil)
        #expect(job.remoteSourceURL == nil)
        #expect(job.completedAt == nil)
    }

    @Test func completedJobDoesNotRequeue() {
        let savedFileURL: URL = URL(filePath: "/tmp/out.md")
        var job: Job = makeJob()
        job.startProcessing()
        job.startDelivery()
        job.complete(
            markdown: "# Done",
            deliveryWarnings: ["warning"],
            savedFileURL: savedFileURL,
            remoteSourceURL: URL(string: "https://s3.example.com/source")!
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
