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
}

private var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
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
    ("testDamagedSessionDoesNotHideHealthyProducts", suite.testDamagedSessionDoesNotHideHealthyProducts)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(checks.count) checks; \(failures) failures")
if failures != 0 { exit(1) }
