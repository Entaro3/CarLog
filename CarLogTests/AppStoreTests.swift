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
        XCTAssertEqual(store.startingOdometer(vehicleID: car.id, editing: record), 1000)
        record.note = "Updated note"
        record.distance = record.odometer! - store.startingOdometer(vehicleID: car.id, editing: record)
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
        XCTAssertEqual(store.startingOdometer(vehicleID: car.id, editing: old), 1000)
        XCTAssertEqual(store.startingOdometer(vehicleID: car.id, editing: nil), 1300)
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
        store.addFuel(fuel(vehicle(), day: 2, odometer: 1200, liters: 100, full: false))
        let full = fuel(car, day: 3, odometer: 1600, liters: 30)
        store.addFuel(full)
        XCTAssertEqual(try XCTUnwrap(store.fuelEfficiency(for: full)), 15, accuracy: 0.0001)
        XCTAssertNil(store.fuelEfficiency(for: partial))
    }

    @MainActor func testFuelEfficiencyStopsAtMostRecentFullTank() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
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
        let first = fuel(car, day: 1, odometer: 1000)
        let second = fuel(car, day: 2, odometer: 1200)
        let third = fuel(car, day: 3, odometer: 1600)
        [first, second, third].forEach(store.addFuel)
        XCTAssertEqual(try XCTUnwrap(store.averageFuelEfficiency(for: [first, second, third])), 15, accuracy: 0.0001)
        XCTAssertNil(store.averageFuelEfficiency(for: [first]))
    }

    @MainActor func testInvalidLatestOdometerDoesNotFallBackToOlderFullTank() async throws {
        let (store, _) = try makeStore()
        let car = vehicle()
        store.addFuel(fuel(car, day: 1, odometer: 1000))
        store.addFuel(fuel(car, day: 2, odometer: 1400))
        let invalid = fuel(car, day: 3, odometer: 1300)
        store.addFuel(invalid)
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
}
