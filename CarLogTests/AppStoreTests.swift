import XCTest
import UIKit
@testable import CarLog

final class AppStoreTests: XCTestCase {
    @MainActor private func makeStore() throws -> (AppStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (AppStore(fileURL: directory.appendingPathComponent("data.json"),
                         photoDirectoryURL: directory.appendingPathComponent("photos")), directory)
    }

    private func vehicle(odometer: Double = 1000) -> Vehicle {
        Vehicle(name: "Test", nickname: "", bodyType: .compact, fuelType: .regular,
                odometer: odometer, primaryColorHex: "007AFF", mood: .standard, isPrimary: true)
    }

    private func trip(_ vehicle: Vehicle, odometer: Double = 1100, distance: Double = 100) -> TripRecord {
        TripRecord(vehicleID: vehicle.id, date: Date(), distance: distance,
                   odometer: odometer, mode: .odometer, purpose: "", note: "")
    }

    private func fuel(_ vehicle: Vehicle, day: Int, odometer: Double, liters: Double = 20, full: Bool = true) -> FuelRecord {
        FuelRecord(vehicleID: vehicle.id, date: Date(timeIntervalSince1970: Double(day) * 86400),
                   liters: liters, totalPrice: liters * 170, odometer: odometer,
                   isFull: full, station: "", note: "")
    }

    @MainActor private func export(_ store: AppStore) throws -> URL {
        let url = try store.exportURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func decode(_ url: URL) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppData.self, from: Data(contentsOf: url))
    }

    @MainActor func testLatestOdometerRecordCanKeepItsDistanceWhenEditingNote() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addVehicle(car)
        var record = trip(car)
        store.addTrip(record)
        record.note = "Updated note"
        record.distance = 0 // The store, not the editor, derives ODO distances.
        store.updateTrip(record)
        XCTAssertEqual(store.data.trips.first?.distance, 100)
        XCTAssertEqual(store.data.trips.first?.note, "Updated note")
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testHistoricalRecordDoesNotUseCurrentVehicleOdometer() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addVehicle(car)
        let old = trip(car)
        store.addTrip(old)
        store.addTrip(trip(car, odometer: 1300, distance: 200))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == old.id })?.distance, 100)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1300)
    }

    @MainActor func testCorrectingLatestOdometerDownwardUpdatesVehicle() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addVehicle(car)
        var record = trip(car)
        store.addTrip(record)
        record.odometer = 1090
        record.distance = 90
        store.updateTrip(record)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1090)
    }

    @MainActor func testPartialFillIsIncludedBetweenFullTanksAndOtherCarsAreExcluded() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addVehicle(car)
        store.addFuel(fuel(car, day: 1, odometer: 1000))
        let partial = fuel(car, day: 2, odometer: 1200, liters: 10, full: false)
        store.addFuel(partial)
        let otherCar = vehicle()
        XCTAssertTrue(store.addVehicle(otherCar))
        XCTAssertTrue(store.addFuel(fuel(otherCar, day: 2, odometer: 1200, liters: 100, full: false)))
        let full = fuel(car, day: 3, odometer: 1600, liters: 30)
        store.addFuel(full)
        XCTAssertEqual(try XCTUnwrap(store.fuelEfficiency(for: full)), 15, accuracy: 0.0001)
        XCTAssertNil(store.fuelEfficiency(for: partial))
    }

    @MainActor func testFuelEfficiencyStopsAtMostRecentFullTank() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        store.addFuel(fuel(car, day: 1, odometer: 1000))
        store.addFuel(fuel(car, day: 2, odometer: 1200, liters: 10, full: false))
        store.addFuel(fuel(car, day: 3, odometer: 1600, liters: 30))
        let latest = fuel(car, day: 4, odometer: 1800, liters: 20)
        store.addFuel(latest)
        XCTAssertEqual(try XCTUnwrap(store.fuelEfficiency(for: latest)), 10, accuracy: 0.0001)
    }

    @MainActor func testAverageUsesCountAndIgnoresUncalculableRecords() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let first = fuel(car, day: 1, odometer: 1000)
        let second = fuel(car, day: 2, odometer: 1200)
        let third = fuel(car, day: 3, odometer: 1600)
        [first, second, third].forEach { XCTAssertTrue(store.addFuel($0)) }
        XCTAssertEqual(try XCTUnwrap(store.averageFuelEfficiency(for: [first, second, third])), 15, accuracy: 0.0001)
        XCTAssertNil(store.averageFuelEfficiency(for: [first]))
    }

    @MainActor func testInvalidLatestOdometerDoesNotFallBackToOlderFullTank() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        store.addFuel(fuel(car, day: 1, odometer: 1000))
        store.addFuel(fuel(car, day: 2, odometer: 1400))
        let invalid = fuel(car, day: 3, odometer: 1300)
        XCTAssertFalse(store.addFuel(invalid))
        XCTAssertEqual(store.data.fuels.count, 2)
        XCTAssertNil(store.fuelEfficiency(for: invalid))
    }

    @MainActor func testEveryExportIsAnIndependentSnapshotOfLatestData() async throws {
        let (store, _) = try makeStore()
        var car = vehicle()
        store.addVehicle(car)
        let first = try export(store)
        car.name = "Changed"
        store.updateVehicle(car)
        let second = try export(store)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try decode(first).vehicles.first?.name, "Test")
        XCTAssertEqual(try decode(second).vehicles.first?.name, "Changed")
    }

    @MainActor func testPhotoBackupRestoresIntoAnEmptyStoreAndSurvivesReload() async throws {
        let (source, _) = try makeStore()
        var car = vehicle()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        car.photoFilename = try XCTUnwrap(source.saveVehiclePhoto(image, vehicleID: car.id))
        source.addVehicle(car)
        let url = try export(source)
        let backup = try decode(url)
        let imageBytes = try XCTUnwrap(backup.vehiclePhotos?[car.photoFilename!])
        let (destination, directory) = try makeStore()
        try destination.restore(from: url)
        let filename = try XCTUnwrap(destination.data.vehicles.first?.photoFilename)
        XCTAssertNotEqual(filename, car.photoFilename)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("photos/" + filename)), imageBytes)
        XCTAssertNil(destination.data.vehiclePhotos)
        let reloaded = AppStore(fileURL: directory.appendingPathComponent("data.json"),
                                photoDirectoryURL: directory.appendingPathComponent("photos"))
        XCTAssertEqual(reloaded.data.vehicles.first?.photoFilename, filename)
    }

    @MainActor func testLegacyBackupWithoutPhotosStillRestores() async throws {
        let (store, directory) = try makeStore()
        var car = vehicle()
        car.photoFilename = "missing-old-photo.jpg"
        var legacy = AppData()
        legacy.vehicles = [car]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("legacy.json")
        try encoder.encode(legacy).write(to: url)
        try store.restore(from: url)
        XCTAssertEqual(store.data.vehicles.first?.id, car.id)
        XCTAssertNil(store.data.vehicles.first?.photoFilename)
    }

    @MainActor func testCorruptPhotoBackupLeavesExistingDataUntouched() async throws {
        let (store, directory) = try makeStore()
        let original = vehicle()
        store.addVehicle(original)
        let before = try Data(contentsOf: directory.appendingPathComponent("data.json"))
        var replacement = vehicle()
        replacement.photoFilename = "corrupt.jpg"
        var backup = AppData()
        backup.vehicles = [replacement]
        backup.vehiclePhotos = ["corrupt.jpg": Data("not an image".utf8)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("corrupt.json")
        try encoder.encode(backup).write(to: url)
        XCTAssertThrowsError(try store.restore(from: url))
        XCTAssertEqual(store.data.vehicles.first?.id, original.id)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("data.json")), before)
    }

    @MainActor func testFailedDataWriteRollsBackRestoredPhotos() async throws {
        let (source, _) = try makeStore()
        var car = vehicle()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        car.photoFilename = try XCTUnwrap(source.saveVehiclePhoto(image, vehicleID: car.id))
        source.addVehicle(car)
        let url = try export(source)
        let (_, directory) = try makeStore()
        let photos = directory.appendingPathComponent("photos")
        // This parent intentionally does not exist, so persisting restored JSON fails.
        let destination = AppStore(fileURL: directory.appendingPathComponent("missing/data.json"), photoDirectoryURL: photos)
        XCTAssertThrowsError(try destination.restore(from: url))
        XCTAssertTrue(destination.data.vehicles.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: photos.path), [])
    }

    private func datedTrip(_ car: Vehicle, day: Int, distance: Double = 0, odometer: Double? = nil) -> TripRecord {
        TripRecord(vehicleID: car.id, date: Date(timeIntervalSince1970: Double(day) * 86400),
                   distance: distance, odometer: odometer, mode: odometer == nil ? .distance : .odometer,
                   purpose: "", note: "")
    }

    @MainActor func testMixedManualDistanceEditsAndDeletionKeepMeasuredOdometer() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var manual = datedTrip(car, day: 1, distance: 30)
        let measured = datedTrip(car, day: 2, odometer: 1100)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertTrue(store.addTrip(measured))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 70)
        manual.distance = 40
        XCTAssertTrue(store.updateTrip(manual))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 60)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertTrue(store.deleteTrip(id: manual.id))
        XCTAssertEqual(store.data.trips.first?.distance, 100)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testEditingAndDeletingEarlierOdoRecomputesFollowingTrip() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var first = datedTrip(car, day: 1, odometer: 1100)
        let second = datedTrip(car, day: 2, odometer: 1300)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(second))
        first.odometer = 1150
        XCTAssertTrue(store.updateTrip(first))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == first.id })?.distance, 150)
        XCTAssertEqual(store.data.trips.first(where: { $0.id == second.id })?.distance, 150)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1300)
        XCTAssertTrue(store.deleteTrip(id: first.id))
        XCTAssertEqual(store.data.trips.first?.distance, 300)
        XCTAssertTrue(store.deleteTrip(id: second.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
    }

    @MainActor func testDeletingLatestOdoKeepsRemainingManualDistance() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let first = datedTrip(car, day: 1, odometer: 1100)
        let manual = datedTrip(car, day: 2, distance: 30)
        let last = datedTrip(car, day: 3, odometer: 1200)
        [first, manual, last].forEach { XCTAssertTrue(store.addTrip($0)) }
        XCTAssertTrue(store.deleteTrip(id: last.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1130)
        XCTAssertTrue(store.deleteTrip(id: first.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1030)
    }

    @MainActor func testManualDistanceAfterLastReadingIsAddedAndRemoved() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, odometer: 1100)))
        var manual = datedTrip(car, day: 2, distance: 30)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1130)
        manual.distance = 45
        XCTAssertTrue(store.updateTrip(manual))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1145)
        XCTAssertTrue(store.deleteTrip(id: manual.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testBackdatedInsertAndDateChangeReorderHistory() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let last = datedTrip(car, day: 3, odometer: 1300)
        XCTAssertTrue(store.addTrip(last))
        var manual = datedTrip(car, day: 2, distance: 40)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == last.id })?.distance, 260)
        manual.date = Date(timeIntervalSince1970: 4 * 86400)
        XCTAssertTrue(store.updateTrip(manual))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == last.id })?.distance, 300)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1340)
    }

    @MainActor func testSwitchingInputModesRecomputesLaterDistances() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var first = datedTrip(car, day: 1, distance: 30)
        let last = datedTrip(car, day: 2, odometer: 1100)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(last))
        first.odometer = 1040
        first.mode = .odometer
        first.distance = 0
        XCTAssertTrue(store.updateTrip(first))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == last.id })?.distance, 60)
        first.odometer = nil
        first.mode = .distance
        first.distance = 20
        XCTAssertTrue(store.updateTrip(first))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == last.id })?.distance, 80)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testFuelOdoEditAndDeletionRecomputeVehicleWithoutDoubleCountingTrips() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var fill = fuel(car, day: 1, odometer: 1050)
        XCTAssertTrue(store.addFuel(fill))
        let measured = datedTrip(car, day: 2, odometer: 1100)
        XCTAssertTrue(store.addTrip(measured))
        // Fuel records must not consume distance from a later driving record.
        XCTAssertEqual(store.data.trips.first?.distance, 100)
        fill.odometer = 1080
        XCTAssertTrue(store.updateFuel(fill))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertTrue(store.deleteTrip(id: measured.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1080)
        fill.odometer = 1060
        XCTAssertTrue(store.updateFuel(fill))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1060)
        XCTAssertTrue(store.deleteFuel(id: fill.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
    }

    @MainActor func testFuelAnchorAbsorbsEarlierManualChangesButKeepsLaterManualDistance() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var before = datedTrip(car, day: 1, distance: 30)
        XCTAssertTrue(store.addTrip(before))
        let fill = fuel(car, day: 2, odometer: 1100)
        XCTAssertTrue(store.addFuel(fill))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 3, distance: 20)))
        before.distance = 50
        XCTAssertTrue(store.updateTrip(before))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1120)
        XCTAssertTrue(store.deleteFuel(id: fill.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1070)
    }

    @MainActor func testContradictoryEditLeavesHistoryAndFileUntouched() async throws {
        let (store, directory) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var manual = datedTrip(car, day: 1, distance: 30)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 2, odometer: 1100)))
        let original = try Data(contentsOf: directory.appendingPathComponent("data.json"))
        manual.distance = 150
        XCTAssertFalse(store.updateTrip(manual))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == manual.id })?.distance, 30)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("data.json")), original)
        XCTAssertNotNil(store.lastError)
    }

    @MainActor func testSameTimestampOrderIsStableAcrossReload() async throws {
        let (store, directory) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let measured = datedTrip(car, day: 1, odometer: 1100)
        XCTAssertTrue(store.addTrip(measured))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, distance: 30)))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 70)
        let reloaded = AppStore(fileURL: directory.appendingPathComponent("data.json"))
        XCTAssertEqual(reloaded.data.trips.first(where: { $0.id == measured.id })?.distance, 70)
        XCTAssertEqual(reloaded.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testChangingRegistrationOdoRecomputesFirstSegmentOnly() async throws {
        let (store, _) = try makeStore()
        var car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, odometer: 1100)))
        car.initialOdometer = 1020
        XCTAssertTrue(store.updateVehicle(car))
        XCTAssertEqual(store.data.trips.first?.distance, 80)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testLegacyBaselineMigratesOnceAndSurvivesDeletingAllRecords() async throws {
        let (_, directory) = try makeStore()
        var legacy = AppData()
        let car = vehicle(odometer: 1120)
        let measured = datedTrip(car, day: 2, distance: 70, odometer: 1100)
        let manual = datedTrip(car, day: 1, distance: 30)
        let tail = datedTrip(car, day: 3, distance: 20)
        legacy.vehicles = [car]
        legacy.trips = [tail, measured, manual]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("data.json")
        try encoder.encode(legacy).write(to: url)
        let migrated = AppStore(fileURL: url)
        XCTAssertEqual(migrated.selectedVehicle?.initialOdometer, 1000)
        XCTAssertEqual(migrated.selectedVehicle?.odometer, 1120)
        for record in [tail, measured, manual] { XCTAssertTrue(migrated.deleteTrip(id: record.id)) }
        XCTAssertEqual(migrated.selectedVehicle?.odometer, 1000)
        let reloaded = AppStore(fileURL: url)
        XCTAssertEqual(reloaded.selectedVehicle?.initialOdometer, 1000)
        XCTAssertEqual(reloaded.selectedVehicle?.odometer, 1000)
    }

    @MainActor func testManualOnlyLegacyBaselineAndVehicleIsolation() async throws {
        let (_, directory) = try makeStore()
        let car = vehicle(odometer: 1050)
        let other = vehicle(odometer: 2000)
        let first = datedTrip(car, day: 1, distance: 50)
        var legacy = AppData()
        legacy.vehicles = [car, other]
        legacy.trips = [first]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("data.json")
        try encoder.encode(legacy).write(to: url)
        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.deleteTrip(id: first.id))
        XCTAssertEqual(store.data.vehicles.first(where: { $0.id == car.id })?.odometer, 1000)
        XCTAssertEqual(store.data.vehicles.first(where: { $0.id == other.id })?.odometer, 2000)
    }

    @MainActor func testFuelWithoutOdoDoesNotResetVehicle() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, distance: 30)))
        XCTAssertTrue(store.addFuel(fuel(car, day: 2, odometer: 0)))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1030)
    }

    @MainActor func testAtomicReplacementDoesNotDropEditedRecordWhenValidationFails() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let first = datedTrip(car, day: 1, distance: 30)
        let second = datedTrip(car, day: 2, distance: 20)
        [first, second, datedTrip(car, day: 3, odometer: 1100)].forEach { XCTAssertTrue(store.addTrip($0)) }
        var replacement = first
        replacement.distance = 150
        XCTAssertFalse(store.replaceTrip(replacement, removing: second.id))
        XCTAssertEqual(store.data.trips.count, 3)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testDecimalDistancesDoNotRejectAnEqualOdoDueToRounding() async throws {
        let (store, _) = try makeStore()
        let car = vehicle(odometer: 0)
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, distance: 0.1)))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 2, distance: 0.2)))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 3, odometer: 0.3)))
        XCTAssertEqual(store.selectedVehicle?.odometer, 0.3)
        XCTAssertEqual(store.data.trips.last?.distance, 0)
    }

    @MainActor func testMixedHistoryRemainsConsistentAfterBackupRestoreAndFurtherEdits() async throws {
        let (source, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(source.addVehicle(car))
        var manual = datedTrip(car, day: 1, distance: 30)
        let measured = datedTrip(car, day: 2, odometer: 1100)
        XCTAssertTrue(source.addTrip(manual))
        XCTAssertTrue(source.addTrip(measured))
        let backup = try export(source)
        let (destination, _) = try makeStore()
        try destination.restore(from: backup)
        manual.distance = 40
        XCTAssertTrue(destination.updateTrip(manual))
        XCTAssertEqual(destination.data.trips.first(where: { $0.id == measured.id })?.distance, 60)
        XCTAssertEqual(destination.selectedVehicle?.odometer, 1100)
        XCTAssertTrue(destination.deleteTrip(id: measured.id))
        XCTAssertEqual(destination.selectedVehicle?.odometer, 1040)
    }

    @MainActor func testVehicleSettingCorrectionCanReduceManualDriftWithoutRewritingTrips() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let manual = datedTrip(car, day: 1, distance: 120)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertTrue(store.updateVehicle(car, correctedOdometer: 1100, correctionDate: Date(timeIntervalSince1970: 2 * 86400)))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertEqual(store.data.trips.first?.distance, 120)
        XCTAssertEqual(store.selectedVehicle?.odometerCorrections?.first?.adjustment, -20)
        let measured = datedTrip(car, day: 3, odometer: 1150)
        XCTAssertTrue(store.addTrip(measured))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 50)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1150)
    }

    @MainActor func testCorrectionEditsAndDeletionRecalculateFollowingOdoDistance() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, distance: 30)))
        XCTAssertTrue(store.updateVehicle(car, correctedOdometer: 1040, correctionDate: Date(timeIntervalSince1970: 2 * 86400)))
        let measured = datedTrip(car, day: 3, odometer: 1100)
        XCTAssertTrue(store.addTrip(measured))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 60)
        var correction = try XCTUnwrap(store.selectedVehicle?.odometerCorrections?.first)
        correction.odometer = 1050
        XCTAssertTrue(store.updateOdometerCorrection(vehicleID: car.id, correction: correction))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 50)
        XCTAssertTrue(store.deleteOdometerCorrection(vehicleID: car.id, id: correction.id))
        XCTAssertEqual(store.data.trips.first(where: { $0.id == measured.id })?.distance, 70)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testCorrectionCannotConcealAnEarlierIncorrectMeasuredOdo() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(datedTrip(car, day: 1, odometer: 1100)))
        XCTAssertFalse(store.updateVehicle(car, correctedOdometer: 1090, correctionDate: Date(timeIntervalSince1970: 2 * 86400)))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertTrue(store.selectedVehicle?.odometerCorrections?.isEmpty ?? true)
    }

    @MainActor func testCorrectionAndTrailingManualDistanceSurviveBackupAndReload() async throws {
        let (source, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(source.addVehicle(car))
        XCTAssertTrue(source.updateVehicle(car, correctedOdometer: 1050, correctionDate: Date(timeIntervalSince1970: 86400)))
        XCTAssertTrue(source.addTrip(datedTrip(car, day: 2, distance: 20)))
        let backup = try export(source)
        let (destination, directory) = try makeStore()
        try destination.restore(from: backup)
        XCTAssertEqual(destination.selectedVehicle?.odometer, 1070)
        let reloaded = AppStore(fileURL: directory.appendingPathComponent("data.json"))
        XCTAssertEqual(reloaded.selectedVehicle?.odometer, 1070)
        let correction = try XCTUnwrap(reloaded.selectedVehicle?.odometerCorrections?.first)
        XCTAssertTrue(reloaded.deleteOdometerCorrection(vehicleID: car.id, id: correction.id))
        XCTAssertEqual(reloaded.selectedVehicle?.odometer, 1020)
    }
}
