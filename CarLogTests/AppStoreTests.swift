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

    @MainActor func testEditingOdoRecordDistanceDownwardUpdatesVehicle() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addVehicle(car)
        var record = trip(car)
        store.addTrip(record)
        record.distance = 90
        store.updateTrip(record)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1090)
        XCTAssertEqual(store.data.trips.first?.odometer, 1100)
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

    @MainActor func testDescendingFuelOdoDoesNotChangeVehicleMileage() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        store.addFuel(fuel(car, day: 1, odometer: 1000))
        store.addFuel(fuel(car, day: 2, odometer: 1400))
        let invalid = fuel(car, day: 3, odometer: 1300)
        XCTAssertTrue(store.addFuel(invalid))
        XCTAssertEqual(store.data.fuels.count, 3)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
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

    private func distanceTrip(_ car: Vehicle, distance: Double, day: Int = 1) -> TripRecord {
        TripRecord(vehicleID: car.id, date: Date(timeIntervalSince1970: Double(day) * 86400),
                   distance: distance, odometer: nil, mode: .distance, purpose: "", note: "")
    }

    @MainActor func testDeleteAndRegisterActualOdoAgainRestoresTheDistance() async throws {
        let (store, _) = try makeStore()
        let car = vehicle(odometer: 10000)
        XCTAssertTrue(store.addVehicle(car))
        let first = trip(car, odometer: 10100, distance: 999)
        let second = trip(car, odometer: 10180, distance: 999)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(second))
        XCTAssertEqual(store.data.trips.map(\.distance), [100, 80])
        XCTAssertTrue(store.deleteTrip(id: first.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 10080)
        XCTAssertEqual(store.data.trips.first?.distance, 80)
        XCTAssertEqual(store.data.trips.first?.odometer, 10180)
        let replacement = trip(car, odometer: 10180)
        XCTAssertTrue(store.addTrip(replacement))
        XCTAssertEqual(store.data.trips.last?.distance, 100)
        XCTAssertEqual(store.selectedVehicle?.odometer, 10180)
    }

    @MainActor func testEditingOldDistanceAppliesOnlyItsDeltaAndKeepsOtherRecords() async throws {
        let (store, _) = try makeStore()
        let car = vehicle(odometer: 10000)
        XCTAssertTrue(store.addVehicle(car))
        var first = trip(car, odometer: 10100)
        let second = trip(car, odometer: 10180)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(second))
        let later = try XCTUnwrap(store.data.trips.last)
        first.distance = 120
        first.odometer = nil // Editing cannot discard or re-interpret the original ODO.
        first.mode = .distance
        XCTAssertTrue(store.updateTrip(first))
        XCTAssertEqual(store.selectedVehicle?.odometer, 10200)
        XCTAssertEqual(store.data.trips.first?.odometer, 10100)
        XCTAssertEqual(store.data.trips.first?.mode, .odometer)
        XCTAssertEqual(store.data.trips.last, later)
        first.distance = 80
        XCTAssertTrue(store.updateTrip(first))
        XCTAssertEqual(store.selectedVehicle?.odometer, 10160)
        XCTAssertEqual(store.data.trips.last, later)
    }

    @MainActor func testManualAndOdoRecordsUseSameDeltaRule() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var manual = distanceTrip(car, distance: 30)
        let measured = trip(car)
        XCTAssertTrue(store.addTrip(manual))
        XCTAssertTrue(store.addTrip(measured))
        XCTAssertEqual(store.data.trips.last?.distance, 70)
        manual.distance = 40
        XCTAssertTrue(store.updateTrip(manual))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1110)
        XCTAssertEqual(store.data.trips.last?.distance, 70)
        XCTAssertTrue(store.deleteTrip(id: measured.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1040)
        XCTAssertTrue(store.deleteTrip(id: manual.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
    }

    @MainActor func testDateOnlyEditDoesNotChangeMileageOrOtherRecords() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var record = distanceTrip(car, distance: 30)
        XCTAssertTrue(store.addTrip(record))
        let measured = trip(car)
        XCTAssertTrue(store.addTrip(measured))
        let later = try XCTUnwrap(store.data.trips.last)
        record.date = Date.distantFuture
        record.note = "Moved date only"
        XCTAssertTrue(store.updateTrip(record))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
        XCTAssertEqual(store.data.trips.last, later)
    }

    @MainActor func testBackdatedNewOdoStillUsesCurrentVehicleValue() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(trip(car)))
        var backdated = trip(car, odometer: 1150)
        backdated.date = Date.distantPast
        XCTAssertTrue(store.addTrip(backdated))
        XCTAssertEqual(store.data.trips.last?.distance, 50)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1150)
    }

    @MainActor func testSettingVehicleOdoDirectlyKeepsDistancesAndFutureEditsUseDeltas() async throws {
        let (store, _) = try makeStore()
        var car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        var record = distanceTrip(car, distance: 100)
        XCTAssertTrue(store.addTrip(record))
        car.odometer = 1050
        XCTAssertTrue(store.updateVehicle(car))
        XCTAssertEqual(store.data.trips.first?.distance, 100)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1050)
        record.distance = 120
        XCTAssertTrue(store.updateTrip(record))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1070)
        XCTAssertTrue(store.deleteTrip(id: record.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 950)
        XCTAssertTrue(store.addTrip(trip(car, odometer: 1100)))
        XCTAssertEqual(store.data.trips.last?.distance, 150)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1100)
    }

    @MainActor func testFuelEditsAndDeletionDoNotChangeVehicleOdoOrTripDistances() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        XCTAssertTrue(store.addTrip(distanceTrip(car, distance: 30)))
        let tripsBefore = store.data.trips
        var fill = fuel(car, day: 2, odometer: 1100)
        XCTAssertTrue(store.addFuel(fill))
        fill.odometer = 1200
        XCTAssertTrue(store.updateFuel(fill))
        XCTAssertTrue(store.deleteFuel(id: fill.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1030)
        XCTAssertEqual(store.data.trips, tripsBefore)
    }

    @MainActor func testRepeatedDeletionDoesNotSubtractTwice() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let record = distanceTrip(car, distance: 30)
        XCTAssertTrue(store.addTrip(record))
        XCTAssertTrue(store.deleteTrip(id: record.id))
        XCTAssertFalse(store.deleteTrip(id: record.id))
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
    }

    @MainActor func testInvalidNewOdoDoesNotChangeDataOrDisk() async throws {
        let (store, directory) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let before = try Data(contentsOf: directory.appendingPathComponent("data.json"))
        XCTAssertFalse(store.addTrip(trip(car, odometer: 900)))
        XCTAssertFalse(store.addTrip(trip(car, odometer: 1000)))
        XCTAssertTrue(store.data.trips.isEmpty)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1000)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("data.json")), before)
    }

    @MainActor func testNegativeResultIsRejectedWithoutPartialChanges() async throws {
        let (store, directory) = try makeStore()
        var car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let record = distanceTrip(car, distance: 100)
        XCTAssertTrue(store.addTrip(record))
        car.odometer = 50
        XCTAssertTrue(store.updateVehicle(car))
        let before = try Data(contentsOf: directory.appendingPathComponent("data.json"))
        XCTAssertFalse(store.deleteTrip(id: record.id))
        XCTAssertEqual(store.data.trips.count, 1)
        XCTAssertEqual(store.selectedVehicle?.odometer, 50)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("data.json")), before)
    }

    @MainActor func testSameDayOverwriteAppliesNetChangeOnce() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        XCTAssertTrue(store.addVehicle(car))
        let first = distanceTrip(car, distance: 30)
        let edited = distanceTrip(car, distance: 40, day: 2)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(edited))
        var replacement = first
        replacement.distance = -1
        XCTAssertFalse(store.replaceTrip(replacement, removing: edited.id))
        XCTAssertEqual(store.data.trips.count, 2)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1070)
        replacement.distance = 50
        XCTAssertTrue(store.replaceTrip(replacement, removing: edited.id))
        XCTAssertEqual(store.data.trips.count, 1)
        XCTAssertEqual(store.selectedVehicle?.odometer, 1050)
    }

    @MainActor func testLegacyDataAndBackupPreserveSavedMileageWithoutRecalculation() async throws {
        let (_, directory) = try makeStore()
        var car = vehicle(odometer: 1050)
        car.initialOdometer = 500
        car.odometerCorrections = [OdometerCorrection(date: Date(), odometer: 1400)]
        var legacy = AppData()
        legacy.vehicles = [car]
        // The retained ODO is intentionally different from today's vehicle value.
        legacy.trips = [trip(car, odometer: 1100, distance: 80)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("data.json")
        let raw = try encoder.encode(legacy)
        try raw.write(to: url)
        let loaded = AppStore(fileURL: url)
        XCTAssertEqual(loaded.selectedVehicle?.odometer, 1050)
        XCTAssertEqual(loaded.data.trips.first?.distance, 80)
        XCTAssertEqual(try Data(contentsOf: url), raw)
        let backup = try export(loaded)
        let (restored, _) = try makeStore()
        try restored.restore(from: backup)
        XCTAssertEqual(restored.selectedVehicle?.odometer, 1050)
        XCTAssertEqual(restored.data.trips.first?.distance, 80)
        XCTAssertEqual(restored.selectedVehicle?.odometerCorrections?.first?.odometer, 1400)
        XCTAssertTrue(restored.deleteTrip(id: legacy.trips[0].id))
        XCTAssertEqual(restored.selectedVehicle?.odometer, 970)
    }

    @MainActor func testChangingOneVehicleDoesNotChangeAnother() async throws {
        let (store, _) = try makeStore()
        let first = vehicle()
        let second = vehicle(odometer: 2000)
        XCTAssertTrue(store.addVehicle(first))
        XCTAssertTrue(store.addVehicle(second))
        let record = distanceTrip(first, distance: 30)
        XCTAssertTrue(store.addTrip(record))
        XCTAssertTrue(store.deleteTrip(id: record.id))
        XCTAssertEqual(store.data.vehicles.map(\.odometer), [1000, 2000])
    }

    @MainActor func testDecimalSubtractionCanReturnToZero() async throws {
        let (store, _) = try makeStore()
        var car = vehicle(odometer: 0)
        XCTAssertTrue(store.addVehicle(car))
        let first = distanceTrip(car, distance: 0.1)
        let second = distanceTrip(car, distance: 0.2, day: 2)
        XCTAssertTrue(store.addTrip(first))
        XCTAssertTrue(store.addTrip(second))
        car.odometer = 0.3
        XCTAssertTrue(store.updateVehicle(car))
        XCTAssertTrue(store.deleteTrip(id: first.id))
        XCTAssertTrue(store.deleteTrip(id: second.id))
        XCTAssertEqual(try XCTUnwrap(store.selectedVehicle?.odometer), 0, accuracy: 0.000000001)
    }

    @MainActor func testFailedPersistenceDoesNotApplyVehicleOrMileageChange() async throws {
        let (_, directory) = try makeStore()
        let store = AppStore(fileURL: directory.appendingPathComponent("missing/data.json"))
        XCTAssertFalse(store.addVehicle(vehicle()))
        XCTAssertTrue(store.data.vehicles.isEmpty)
        XCTAssertNotNil(store.lastError)
    }
}

final class MeterOCRTests: XCTestCase {
    private func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.1, height: CGFloat = 0.04) -> MeterTextFragment {
        MeterTextFragment(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    private func tokenize(_ text: String) -> [MeterTextFragment] {
        MeterReadingParser.fragments(in: text) { range in
            let nsRange = NSRange(range, in: text)
            let total = CGFloat(text.utf16.count)
            return CGRect(x: CGFloat(nsRange.location) / total * 0.9, y: 0.5,
                          width: CGFloat(nsRange.length) / total * 0.9, height: 0.05)
        }
    }

    func testStackedOdoAndTripAreSeparatedRegardlessOfObservationOrder() throws {
        let readings = MeterReadingParser.readings(from: [
            fragment("123.4", x: 0.4, y: 0.3),
            fragment("ODO", x: 0.2, y: 0.7),
            fragment("TRIP A", x: 0.2, y: 0.3),
            fragment("12345", x: 0.4, y: 0.7)
        ])
        XCTAssertEqual(readings.first { $0.kind == .odometer }?.value, 12345)
        XCTAssertEqual(readings.first { $0.kind == .tripA }?.value, 123.4)
    }

    func testSideBySideOdoAndTripAreSeparated() throws {
        let readings = MeterReadingParser.readings(from: [
            fragment("ODO", x: 0.05, y: 0.5),
            fragment("12345", x: 0.18, y: 0.5),
            fragment("TRIP B", x: 0.6, y: 0.5),
            fragment("456.7", x: 0.75, y: 0.5)
        ])
        XCTAssertEqual(readings.first { $0.kind == .odometer }?.value, 12345)
        XCTAssertEqual(readings.first { $0.kind == .tripB }?.value, 456.7)
    }

    func testMultipleLabelsInOneOcrLineAndCommaSeparatedOdo() throws {
        let readings = MeterReadingParser.readings(from: tokenize("ODO 12,345 km TRIP A 123.4 km"))
        XCTAssertEqual(readings.first { $0.kind == .odometer }?.value, 12345)
        XCTAssertEqual(readings.first { $0.kind == .tripA }?.value, 123.4)
    }

    func testLabelsTouchingDigitsAreParsedWithoutMergingReadings() throws {
        let readings = MeterReadingParser.readings(from: tokenize("ODO12345TRIPA123.4"))
        XCTAssertEqual(Set(readings.map(\.value)), Set([12345, 123.4]))
        XCTAssertFalse(readings.contains { $0.value == 12345123.4 })
    }

    func testDigitsBeforeLabelsAreNotAssignedUsingLabelBeforeNumberAssumption() throws {
        let readings = MeterReadingParser.readings(from: tokenize("12345ODO123.4TRIPA"))
        XCTAssertEqual(readings.count, 2)
        XCTAssertTrue(readings.allSatisfy { $0.kind == .unclassified })
    }

    func testLabelBelowNumberIsAssociatedByPosition() throws {
        let readings = MeterReadingParser.readings(from: [
            fragment("12345", x: 0.35, y: 0.7, width: 0.3),
            fragment("ODO", x: 0.45, y: 0.63)
        ])
        XCTAssertEqual(readings.first { $0.kind == .odometer }?.value, 12345)
    }

    func testSplitTripLetterIsPreserved() throws {
        let readings = MeterReadingParser.readings(from: [
            fragment("TRIP", x: 0.1, y: 0.5, width: 0.08),
            fragment("B", x: 0.2, y: 0.5, width: 0.025),
            fragment("456.7", x: 0.3, y: 0.5)
        ])
        XCTAssertEqual(readings.first { $0.kind == .tripB }?.value, 456.7)
        XCTAssertFalse(readings.contains { $0.kind == .tripA })
    }

    func testAmbiguousNumbersRemainUnclassified() throws {
        let ambiguous = MeterReadingParser.readings(from: [
            fragment("ODO", x: 0.45, y: 0.5),
            fragment("12345", x: 0.45, y: 0.43),
            fragment("54321", x: 0.45, y: 0.57)
        ])
        XCTAssertEqual(ambiguous.count, 2)
        XCTAssertTrue(ambiguous.allSatisfy { $0.kind == .unclassified })
    }

    func testUnlabeledDigitsAreNotAssumedToBeTrip() throws {
        let readings = MeterReadingParser.readings(from: tokenize("12345 km"))
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.kind, .unclassified)
    }

    func testSpeedTemperatureConsumptionAndClockAreNotMileageCandidates() throws {
        let readings = MeterReadingParser.readings(from: tokenize("80 km/h 12:34 25°C 15.2 km/L"))
        XCTAssertTrue(readings.isEmpty)
    }

    func testExpectedReadingIsSuggestedWhenOdoAndTripAreBothPresent() throws {
        let odo = MeterReading(kind: .odometer, value: 12345)
        let trip = MeterReading(kind: .tripA, value: 123.4)
        let scan = MeterScanResult(image: UIImage(), readings: [trip, odo], recognizedText: "")
        XCTAssertEqual(scan.suggestedReading(expectsOdometer: true)?.id, odo.id)
        XCTAssertEqual(scan.suggestedReading(expectsOdometer: false)?.id, trip.id)
    }

    func testMultipleTripOrOdoCandidatesRequireExplicitChoice() throws {
        let scan = MeterScanResult(image: UIImage(), readings: [
            MeterReading(kind: .odometer, value: 12345),
            MeterReading(kind: .odometer, value: 54321),
            MeterReading(kind: .tripA, value: 123.4),
            MeterReading(kind: .tripB, value: 456.7)
        ], recognizedText: "")
        XCTAssertNil(scan.suggestedReading(expectsOdometer: true))
        XCTAssertNil(scan.suggestedReading(expectsOdometer: false))
    }

    func testMissingExpectedLabelDoesNotFallBackToOtherMeterKind() throws {
        let scan = MeterScanResult(image: UIImage(), readings: [
            MeterReading(kind: .tripA, value: 123.4),
            MeterReading(kind: .unclassified, value: 12345)
        ], recognizedText: "")
        XCTAssertNil(scan.suggestedReading(expectsOdometer: true))
        XCTAssertFalse(MeterReadingKind.tripA.matches(expectsOdometer: true))
        XCTAssertFalse(MeterReadingKind.odometer.matches(expectsOdometer: false))
    }
}
