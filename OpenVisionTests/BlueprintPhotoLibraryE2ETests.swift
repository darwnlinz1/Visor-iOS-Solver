// OpenVision - BlueprintPhotoLibraryE2ETests.swift
// Checklist test 1 / lesson 6 + B6 / T7.6 against the REAL photo library:
// Only photos inside Meta/Ray-Ban/Stories albums are accepted; private iPhone Camera Roll photos are ignored.

import XCTest
import Photos
@testable import OpenVision

@MainActor
final class BlueprintPhotoLibraryE2ETests: XCTestCase {

    override func setUp() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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

    func testJustTakenGlassesPhotoInMetaAlbumIsFoundAndPreparedForUpload() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        try await Self.addToLibrary(photo, createdAt: Date(), albumTitle: "Meta View")

        let found = await RecentPhotoScanner.shared.fetchMostRecentPhoto(withinSeconds: SolverIntent.recentPhotoWindow)
        let data = try XCTUnwrap(found, "the scanner must find a photo in the Meta View album")
        let info = try XCTUnwrap(PhotoPayload.imageInfo(data))
        XCTAssertEqual(max(info.width, info.height), PhotoPayload.uploadMaxDimension)
        XCTAssertEqual(info.orientation, 1)
    }

    func testPhotoOutsideMetaAlbumIsNeverPickedUp() async throws {
        // Distinctive width 1444 outside any Meta/Ray-Ban album must never be returned (B6 / T7.6).
        let privatePhoto = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 1444, height: 1080))
        try await Self.addToLibrary(privatePhoto, createdAt: Date(), albumTitle: nil)

        if let found = await RecentPhotoScanner.shared.fetchMostRecentPhoto(withinSeconds: SolverIntent.recentPhotoWindow),
           let info = PhotoPayload.imageInfo(found) {
            XCTAssertNotEqual(info.width, 1444, "a non-Meta Camera Roll photo must never be attached")
        }
    }

    func testAnOldPhotoIsNotTreatedAsTheOneJustTaken() async throws {
        let stale = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 1111, height: 777))
        try await Self.addToLibrary(stale, createdAt: Date().addingTimeInterval(-600), albumTitle: "Meta View")

        if let found = await RecentPhotoScanner.shared.fetchMostRecentPhoto(withinSeconds: SolverIntent.recentPhotoWindow),
           let info = PhotoPayload.imageInfo(found) {
            XCTAssertNotEqual(info.width, 1111, "a 10-minute-old photo must not be attached to a new question")
        }
    }

    func testRepeatedLookupsUseThePrefetchedBytes() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        try await Self.addToLibrary(photo, createdAt: Date(), albumTitle: "Meta View")
        let first = await RecentPhotoScanner.shared.fetchMostRecentPhoto()
        let started = Date()
        let second = await RecentPhotoScanner.shared.fetchMostRecentPhoto()
        XCTAssertEqual(first, second)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    private static func addToLibrary(_ jpeg: Data, createdAt: Date, albumTitle: String?) async throws {
        let album = albumTitle != nil ? try await findOrCreateAlbum(named: albumTitle!) : nil
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
            request.creationDate = createdAt
            if let album, let placeholder = request.placeholderForCreatedAsset,
               let albumChange = PHAssetCollectionChangeRequest(for: album) {
                albumChange.addAssets([placeholder] as NSFastEnumeration)
            }
        }
    }

    private static func findOrCreateAlbum(named title: String) async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        if let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions).firstObject {
            return existing
        }
        var createdID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            createdID = req.placeholderForCreatedAssetCollection.localIdentifier
        }
        if let id = createdID,
           let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return created
        }
        throw NSError(domain: "BlueprintPhotoLibraryE2ETests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create album \(title)"])
    }
}
