// OpenVision - BlueprintPhotoLibraryE2ETests.swift
// Checklist test 1 / lesson 6 against the REAL photo library: a photo that lands in Camera Roll
// (what Meta View does after the temple shutter) is found by RecentPhotoScanner at full
// resolution, and an old photo is not mistaken for "the one I just took".
//
// Needs full Photos access for the host app. CI grants it before the run
// (scripts/e2e/run-simulator-tests.sh → grant_photos_access); without it these skip.

import XCTest
import Photos
@testable import OpenVision

@MainActor
final class BlueprintPhotoLibraryE2ETests: XCTestCase {

    override func setUp() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // Printed on every run so the CI log shows why these tests ran or skipped (PLAN.md N1).
        print("[BlueprintPhotoLibraryE2ETests] Photos authorization (.readWrite): \(status.rawValue) \(Self.name(of: status))")
        try XCTSkipUnless(status == .authorized,
                          "Photos access not granted (status \(status.rawValue) \(Self.name(of: status))); run via scripts/e2e/run-simulator-tests.sh")
    }

    nonisolated private static func name(of status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .limited: return "limited"
        @unknown default: return "unknown"
        }
    }

    func testJustTakenGlassesPhotoIsFoundAndPreparedForUpload() async throws {
        // A distinctive 12 MP frame (the Ray-Ban Meta Gen 2 sensor size).
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        try await Self.addToLibrary(photo, createdAt: Date())

        let found = await RecentPhotoScanner.shared.fetchMostRecentPhoto(withinSeconds: SolverIntent.recentPhotoWindow)
        let data = try XCTUnwrap(found, "the scanner must find a photo synced seconds ago")
        let info = try XCTUnwrap(PhotoPayload.imageInfo(data))
        XCTAssertEqual(max(info.width, info.height), PhotoPayload.uploadMaxDimension, "12 MP prepared at 3072 px (Gemini 3's fixed image budget)")
        XCTAssertEqual(info.orientation, 1, "upright pixels: the model may ignore EXIF rotation")
    }

    func testAnOldPhotoIsNotTreatedAsTheOneJustTaken() async throws {
        // Distinctive size so we can tell it apart from any other recent photo on the device.
        let stale = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 1111, height: 777))
        try await Self.addToLibrary(stale, createdAt: Date().addingTimeInterval(-600))

        if let found = await RecentPhotoScanner.shared.fetchMostRecentPhoto(withinSeconds: SolverIntent.recentPhotoWindow),
           let info = PhotoPayload.imageInfo(found) {
            XCTAssertNotEqual(info.width, 1111, "a 10-minute-old photo must not be attached to a new question")
        }
    }

    func testRepeatedLookupsUseThePrefetchedBytes() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        try await Self.addToLibrary(photo, createdAt: Date())
        let first = await RecentPhotoScanner.shared.fetchMostRecentPhoto()
        let started = Date()
        let second = await RecentPhotoScanner.shared.fetchMostRecentPhoto()
        XCTAssertEqual(first, second)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "the cached photo is returned without decoding again")
    }

    private static func addToLibrary(_ jpeg: Data, createdAt: Date) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
            request.creationDate = createdAt
        }
    }
}
