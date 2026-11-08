import Foundation
import StudioCore

final class StudioCoreTests {
    func testWhiteBalanceGainsNeverExceedCameraLimits() {
        let gains = WhiteBalance.clamp(red: -2, green: 2, blue: 20, maximum: 8)
        expectEqual(gains.red, 1)
        expectEqual(gains.green, 2)
        expectEqual(gains.blue, 8)
    }

    func testInvalidGainsFallBackToNeutral() {
        let gains = WhiteBalance.clamp(red: .nan, green: .infinity, blue: 0, maximum: 4)
        expectEqual(gains.red, 1)
        expectEqual(gains.green, 1)
        expectEqual(gains.blue, 1)
    }

    func testMotionIsUnknownBeforeSensorReports() {
        expectEqual(CaptureAdvice.evaluate(iso: 80, seconds: 1 / 200, rotation: nil, focusing: false), .motionUnknown)
    }

    func testSlowExposureWarnsEvenWhenPhoneIsStill() {
        expectEqual(CaptureAdvice.evaluate(iso: 100, seconds: 1 / 20, rotation: 0, focusing: false), .slowShutter)
    }

    func testHighISOWarnsAboutLightInsteadOfPromisingSharpness() {
        expectEqual(CaptureAdvice.evaluate(iso: 1500, seconds: 1 / 200, rotation: 0.01, focusing: false), .lowLight)
    }

    func testMovementAndFocusHavePriorityOverLightAdvice() {
        expectEqual(CaptureAdvice.evaluate(iso: 1600, seconds: 0.1, rotation: 1, focusing: true), .focusing)
        expectEqual(CaptureAdvice.evaluate(iso: 1600, seconds: 0.1, rotation: 1, focusing: false), .moving)
    }

    func testGoodConditionsAreNotASharpnessScore() {
        expectEqual(CaptureAdvice.evaluate(iso: 80, seconds: 1 / 200, rotation: 0.01, focusing: false), .steady)
    }

    func testProductNamesCannotEscapeLocalDirectory() {
        expectEqual(ProductSession.safeName("../../Gucci / polo"), "Gucci-polo")
        expectEqual(ProductSession.safeName("   "), "Prodotto")
    }

    func testShotRecordsKeepActualDimensionsAndRAWPair() throws {
        let shot = ShotRecord(id: UUID(), kind: .label, capturedAt: Date(), jpeg: "one.jpg", raw: "one.dng", width: 4032, height: 3024)
        let decoded = try JSONDecoder().decode(ShotRecord.self, from: JSONEncoder().encode(shot))
        expectEqual(decoded.width, 4032)
        expectEqual(decoded.raw, "one.dng")
        expectEqual(decoded.kind, .label)
    }

    func testDuplicateShotsDoNotInflateChecklistProgress() {
        var product = ProductSession(name: "Celine bianca")
        product.shots = [ShotKind.front, .front, .label].map {
            ShotRecord(id: UUID(), kind: $0, capturedAt: Date(), jpeg: "file.jpg", raw: nil, width: 4000, height: 3000)
        }
        expectEqual(product.completedKinds.count, 2)
        expectEqual(product.nextKind, .back)
    }

    func testProductManifestSurvivesRoundTrip() throws {
        let product = ProductSession(name: "Balenciaga nera")
        let data = try JSONEncoder().encode(product)
        let recovered = try JSONDecoder().decode(ProductSession.self, from: data)
        expectEqual(recovered.id, product.id)
        expectEqual(recovered.name, product.name)
        expectTrue(recovered.shots.isEmpty)
    }

    func testSavePreservesOriginalBytesAndReloadsBothFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let product = try disk.create(name: "Gucci bianca")
        let original = Data([0xFF, 0xD8, 0x01, 0x02])
        let raw = Data([0x49, 0x49, 0x2A, 0x00])
        _ = try disk.append(productID: product.id, kind: .front, jpeg: original, raw: raw, width: 4032, height: 3024)
        let recovered = try unwrap(disk.load().first)
        let shot = try unwrap(recovered.shots.first)
        expectEqual(try Data(contentsOf: disk.folder(for: product.id).appendingPathComponent(shot.jpeg)), original)
        expectEqual(try Data(contentsOf: disk.folder(for: product.id).appendingPathComponent(unwrap(shot.raw))), raw)
    }

    func testFailedSaveDoesNotFabricateAShot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        _ = try disk.create(name: "Celine")
        expectThrows(try disk.append(productID: UUID(), kind: .label, jpeg: Data([1]), raw: nil, width: 1, height: 1))
        expectTrue(try unwrap(disk.load().first).shots.isEmpty)
    }

    func testCorruptManifestIsReportedRatherThanSilentlyLosingProducts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let product = try disk.create(name: "Balenciaga")
        try Data("invalid".utf8).write(to: disk.folder(for: product.id).appendingPathComponent("product.json"))
        let recovered = try disk.recover()
        expectEqual(recovered.unreadable.count, 1)
        expectTrue(recovered.products.isEmpty)
    }

    func testDamagedSessionDoesNotHideHealthyProducts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let healthy = try disk.create(name: "Gucci")
        let damaged = try disk.create(name: "Celine")
        try Data("invalid".utf8).write(to: disk.folder(for: damaged.id).appendingPathComponent("product.json"))
        expectEqual(try disk.load().map(\.id), [healthy.id])
        expectEqual(try disk.recover().unreadable.count, 1)
    }

    // MARK: Level and orientation

    func testUprightPhoneIsLevelAndVertical() throws {
        let reading = try unwrap(Level.reading(x: 0, y: -1, z: 0))
        expectEqual(reading.mode, .upright)
        expectClose(reading.degrees, 0)
        expectTrue(reading.isLevel)
        expectTrue(reading.isVertical)
    }

    func testRollIsMeasuredAndHorizonCounterRotates() throws {
        let angle = 3.0 * .pi / 180
        let reading = try unwrap(Level.reading(x: sin(angle), y: -cos(angle), z: 0))
        expectClose(reading.degrees, 3)
        expectClose(reading.horizon, -3)
        expectClose(reading.reference, 0)
        expectTrue(!reading.isLevel)
    }

    func testLandscapeIsLevelAgainstItsOwnHorizon() throws {
        let reading = try unwrap(Level.reading(x: -1, y: 0, z: 0))
        expectEqual(reading.mode, .upright)
        expectClose(reading.degrees, 0)
        expectClose(reading.horizon, 90)
        expectTrue(reading.isLevel)
    }

    func testForwardTiltIsReportedAsPitch() throws {
        let angle = 10.0 * .pi / 180
        let reading = try unwrap(Level.reading(x: 0, y: -cos(angle), z: -sin(angle)))
        expectClose(abs(reading.pitch), 10)
        expectTrue(!reading.isVertical)
        expectTrue(reading.isLevel)
    }

    func testFlatLayBubbleMovesTowardsTheRaisedEdge() throws {
        let level = try unwrap(Level.reading(x: 0, y: 0, z: -1))
        expectEqual(level.mode, .flat)
        expectClose(level.degrees, 0)
        expectTrue(level.isLevel)
        let angle = 3.0 * .pi / 180
        let rightRaised = try unwrap(Level.reading(x: -sin(angle), y: 0, z: -cos(angle)))
        expectClose(rightRaised.degrees, 3)
        expectTrue(rightRaised.bubbleX > 0)
        let topRaised = try unwrap(Level.reading(x: 0, y: -sin(angle), z: -cos(angle)))
        expectTrue(topRaised.bubbleY < 0)
    }

    func testCameraPointingUpHasNoReading() {
        expectTrue(Level.reading(x: 0, y: 0, z: 1) == nil)
        expectTrue(Level.reading(x: .nan, y: 0, z: 0) == nil)
    }

    func testCaptureAngleFollowsHowThePhoneIsHeld() {
        expectEqual(Level.captureAngle(x: 0, y: -1, z: 0, previous: 0), 90)
        expectEqual(Level.captureAngle(x: -1, y: 0, z: 0, previous: 90), 0)
        expectEqual(Level.captureAngle(x: 1, y: 0, z: 0, previous: 90), 180)
        expectEqual(Level.captureAngle(x: 0, y: 1, z: 0, previous: 90), 270)
    }

    func testFlatAndDiagonalPhonesKeepThePreviousOrientation() {
        expectEqual(Level.captureAngle(x: 0, y: 0, z: -1, previous: 0), 0)
        expectEqual(Level.captureAngle(x: 0.6, y: -0.65, z: 0, previous: 180), 180)
    }

    // MARK: Manual exposure

    func testShutterSliderIsLogarithmicAndRoundTrips() {
        let fastest = 1.0 / 8000, slowest = 1.0
        expectClose(ExposureScale.seconds(at: 0, minimum: fastest, maximum: slowest), fastest)
        expectClose(ExposureScale.seconds(at: 1, minimum: fastest, maximum: slowest), slowest)
        let middle = ExposureScale.seconds(at: 0.5, minimum: fastest, maximum: slowest)
        expectClose(middle, (fastest * slowest).squareRoot())
        expectClose(ExposureScale.position(for: middle, minimum: fastest, maximum: slowest), 0.5)
        expectClose(ExposureScale.position(for: 10, minimum: fastest, maximum: slowest), 1)
    }

    func testShutterLabels() {
        expectEqual(ExposureScale.label(1.0 / 125), "1/125 s")
        expectEqual(ExposureScale.label(2), "2.0 s")
        expectEqual(ExposureScale.label(0), "—")
    }

    // MARK: Live frame analysis

    func testClippedWhitesAndSharpEdgesAreMapped() throws {
        let width = 64, height = 48
        var luma = [UInt8](repeating: 128, count: width * height)
        for y in 0..<height { for x in 0..<(width / 2) { luma[y * width + x] = 255 } }
        let analysis = try unwrap(luma.withUnsafeBytes {
            LumaAnalysis.analyze($0, width: width, height: height, bytesPerRow: width, columns: 32)
        })
        expectEqual(analysis.columns, 32)
        expectEqual(analysis.rows, 24)
        expectClose(analysis.highlights, 0.5)
        expectClose(analysis.histogram.reduce(0, +), 1)
        expectClose(analysis.histogram[31], 0.5)
        let row = 10 * analysis.columns
        expectTrue(analysis.mask[row] & LumaAnalysis.highlightFlag != 0)
        expectTrue(analysis.mask[row] & LumaAnalysis.edgeFlag == 0)
        expectTrue(analysis.mask[row + 15] & LumaAnalysis.edgeFlag != 0)
        expectTrue(analysis.mask[row + 16] & LumaAnalysis.edgeFlag != 0)
        expectTrue(analysis.mask[row + 25] == 0)
    }

    func testEvenGreyHasNoWarnings() throws {
        let width = 40, height = 30, rowBytes = 48
        let luma = [UInt8](repeating: 120, count: rowBytes * height)
        let analysis = try unwrap(luma.withUnsafeBytes {
            LumaAnalysis.analyze($0, width: width, height: height, bytesPerRow: rowBytes, columns: 20)
        })
        expectClose(analysis.highlights, 0)
        expectClose(analysis.shadows, 0)
        expectClose(analysis.histogram[15], 1)
        expectTrue(analysis.mask.allSatisfy { $0 == 0 })
    }

    func testTooSmallOrShortBuffersAreRejected() {
        let luma = [UInt8](repeating: 0, count: 10)
        expectTrue(luma.withUnsafeBytes { LumaAnalysis.analyze($0, width: 8, height: 8, bytesPerRow: 8) } == nil)
    }

    // MARK: Archive management

    func testFilesAreNamedAfterProductAndView() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let product = try disk.create(name: "Celine bianca")
        let saved = try disk.append(productID: product.id, kind: .label, jpeg: Data([1]), raw: Data([2]), width: 3024, height: 4032)
        let shot = try unwrap(saved.shots.first)
        expectEqual(shot.jpeg, "Celine-bianca_01_etichetta.jpg")
        expectEqual(shot.raw, "Celine-bianca_01_etichetta.dng")
    }

    func testDeletingAShotRemovesItsFilesAndNeverReusesAName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let product = try disk.create(name: "Gucci")
        let first = try unwrap(disk.append(productID: product.id, kind: .front, jpeg: Data([1]), raw: Data([9]), width: 1, height: 1).shots.last)
        let second = try unwrap(disk.append(productID: product.id, kind: .back, jpeg: Data([2]), raw: nil, width: 1, height: 1).shots.last)
        let remaining = try disk.deleteShot(productID: product.id, shotID: first.id)
        expectEqual(remaining.shots.map(\.id), [second.id])
        let folder = disk.folder(for: product.id)
        expectTrue(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(first.jpeg).path))
        expectTrue(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(try unwrap(first.raw)).path))
        let third = try unwrap(disk.append(productID: product.id, kind: .logo, jpeg: Data([3]), raw: nil, width: 1, height: 1).shots.last)
        expectEqual(third.jpeg, "Gucci_03_logo.jpg")
        expectEqual(try Data(contentsOf: folder.appendingPathComponent(second.jpeg)), Data([2]))
        expectEqual(try unwrap(disk.load().first).shots.count, 2)
    }

    func testRenameKeepsShotsAndIgnoresEmptyNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let product = try disk.create(name: "Balenciaga")
        _ = try disk.append(productID: product.id, kind: .front, jpeg: Data([1]), raw: nil, width: 1, height: 1)
        expectEqual(try disk.rename(productID: product.id, to: "  Balenciaga nera  ").name, "Balenciaga nera")
        expectEqual(try disk.rename(productID: product.id, to: "   ").name, "Balenciaga nera")
        expectEqual(try unwrap(disk.load().first).shots.count, 1)
    }

    func testDeletingAProductRemovesOnlyThatProduct() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskLibrary(root: directory)
        let kept = try disk.create(name: "Gucci")
        let removed = try disk.create(name: "Celine")
        try disk.deleteProduct(id: removed.id)
        expectEqual(try disk.load().map(\.id), [kept.id])
        expectTrue(!FileManager.default.fileExists(atPath: disk.folder(for: removed.id).path))
    }
}

private var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
    if !(abs(actual - expected) <= tolerance) { failures += 1; print("FAIL \(file):\(line): \(actual) is not close to \(expected)") }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func expectThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); failures += 1; print("FAIL \(file):\(line): expected an error") } catch {}
}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "StudioCoreChecks", code: 1) }
    return value
}
let suite = StudioCoreTests()
let checks: [(String, () throws -> Void)] = [
    ("testWhiteBalanceGainsNeverExceedCameraLimits", suite.testWhiteBalanceGainsNeverExceedCameraLimits),
    ("testInvalidGainsFallBackToNeutral", suite.testInvalidGainsFallBackToNeutral),
    ("testMotionIsUnknownBeforeSensorReports", suite.testMotionIsUnknownBeforeSensorReports),
    ("testSlowExposureWarnsEvenWhenPhoneIsStill", suite.testSlowExposureWarnsEvenWhenPhoneIsStill),
    ("testHighISOWarnsAboutLightInsteadOfPromisingSharpness", suite.testHighISOWarnsAboutLightInsteadOfPromisingSharpness),
    ("testMovementAndFocusHavePriorityOverLightAdvice", suite.testMovementAndFocusHavePriorityOverLightAdvice),
    ("testGoodConditionsAreNotASharpnessScore", suite.testGoodConditionsAreNotASharpnessScore),
    ("testProductNamesCannotEscapeLocalDirectory", suite.testProductNamesCannotEscapeLocalDirectory),
    ("testShotRecordsKeepActualDimensionsAndRAWPair", suite.testShotRecordsKeepActualDimensionsAndRAWPair),
    ("testDuplicateShotsDoNotInflateChecklistProgress", suite.testDuplicateShotsDoNotInflateChecklistProgress),
    ("testProductManifestSurvivesRoundTrip", suite.testProductManifestSurvivesRoundTrip),
    ("testSavePreservesOriginalBytesAndReloadsBothFiles", suite.testSavePreservesOriginalBytesAndReloadsBothFiles),
    ("testFailedSaveDoesNotFabricateAShot", suite.testFailedSaveDoesNotFabricateAShot),
    ("testCorruptManifestIsReportedRatherThanSilentlyLosingProducts", suite.testCorruptManifestIsReportedRatherThanSilentlyLosingProducts),
    ("testDamagedSessionDoesNotHideHealthyProducts", suite.testDamagedSessionDoesNotHideHealthyProducts),
    ("testUprightPhoneIsLevelAndVertical", suite.testUprightPhoneIsLevelAndVertical),
    ("testRollIsMeasuredAndHorizonCounterRotates", suite.testRollIsMeasuredAndHorizonCounterRotates),
    ("testLandscapeIsLevelAgainstItsOwnHorizon", suite.testLandscapeIsLevelAgainstItsOwnHorizon),
    ("testForwardTiltIsReportedAsPitch", suite.testForwardTiltIsReportedAsPitch),
    ("testFlatLayBubbleMovesTowardsTheRaisedEdge", suite.testFlatLayBubbleMovesTowardsTheRaisedEdge),
    ("testCameraPointingUpHasNoReading", suite.testCameraPointingUpHasNoReading),
    ("testCaptureAngleFollowsHowThePhoneIsHeld", suite.testCaptureAngleFollowsHowThePhoneIsHeld),
    ("testFlatAndDiagonalPhonesKeepThePreviousOrientation", suite.testFlatAndDiagonalPhonesKeepThePreviousOrientation),
    ("testShutterSliderIsLogarithmicAndRoundTrips", suite.testShutterSliderIsLogarithmicAndRoundTrips),
    ("testShutterLabels", suite.testShutterLabels),
    ("testClippedWhitesAndSharpEdgesAreMapped", suite.testClippedWhitesAndSharpEdgesAreMapped),
    ("testEvenGreyHasNoWarnings", suite.testEvenGreyHasNoWarnings),
    ("testTooSmallOrShortBuffersAreRejected", suite.testTooSmallOrShortBuffersAreRejected),
    ("testFilesAreNamedAfterProductAndView", suite.testFilesAreNamedAfterProductAndView),
    ("testDeletingAShotRemovesItsFilesAndNeverReusesAName", suite.testDeletingAShotRemovesItsFilesAndNeverReusesAName),
    ("testRenameKeepsShotsAndIgnoresEmptyNames", suite.testRenameKeepsShotsAndIgnoresEmptyNames),
    ("testDeletingAProductRemovesOnlyThatProduct", suite.testDeletingAProductRemovesOnlyThatProduct)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(checks.count) checks; \(failures) failures")
if failures != 0 { exit(1) }
