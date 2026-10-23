import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var selectedVehicleID: UUID?
    @Published var lastError: String?

    private let fileURL: URL
    private let photoDirectoryURL: URL

    init(fileURL: URL? = nil, photoDirectoryURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CarLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("carlog-data.json")
        self.photoDirectoryURL = photoDirectoryURL ?? directory.appendingPathComponent("VehiclePhotos", isDirectory: true)
        load()
        selectedVehicleID = data.vehicles.first(where: \.isPrimary)?.id ?? data.vehicles.first?.id
    }

    var hasVehicles: Bool { !data.vehicles.isEmpty }
    var selectedVehicle: Vehicle? {
        data.vehicles.first(where: { $0.id == selectedVehicleID }) ?? data.vehicles.first
    }

    var appearanceMode: AppAppearance { data.appearanceMode ?? .system }

    static func vehiclePhotoURL(filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CarLog/VehiclePhotos", isDirectory: true).appendingPathComponent(filename)
    }

    static func vehiclePhoto(filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: vehiclePhotoURL(filename: filename).path)
    }

    func saveVehiclePhoto(_ image: UIImage, vehicleID: UUID) -> String? {
        let filename = "vehicle-\(vehicleID.uuidString).jpg"
        let url = photoDirectoryURL.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            lastError = "車両写真を保存できませんでした。"
            return nil
        }
    }

    func trips(for vehicleID: UUID) -> [TripRecord] {
        data.trips.filter { $0.vehicleID == vehicleID }.sorted { $0.date > $1.date }
    }

    func fuels(for vehicleID: UUID) -> [FuelRecord] {
        data.fuels.filter { $0.vehicleID == vehicleID }.sorted { $0.date > $1.date }
    }

    func addVehicle(_ vehicle: Vehicle) {
        var value = vehicle
        if data.vehicles.isEmpty { value.isPrimary = true }
        if value.isPrimary { data.vehicles.indices.forEach { data.vehicles[$0].isPrimary = false } }
        data.vehicles.append(value)
        selectedVehicleID = value.id
        save()
    }

    func updateVehicle(_ vehicle: Vehicle) {
        guard let index = data.vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        if vehicle.isPrimary { data.vehicles.indices.forEach { data.vehicles[$0].isPrimary = false } }
        data.vehicles[index] = vehicle
        save()
    }

    func deleteVehicle(_ vehicle: Vehicle) {
        if let filename = vehicle.photoFilename { try? FileManager.default.removeItem(at: photoDirectoryURL.appendingPathComponent(filename)) }
        data.vehicles.removeAll { $0.id == vehicle.id }
        data.trips.removeAll { $0.vehicleID == vehicle.id }
        data.fuels.removeAll { $0.vehicleID == vehicle.id }
        if !data.vehicles.contains(where: \.isPrimary), !data.vehicles.isEmpty { data.vehicles[0].isPrimary = true }
        selectedVehicleID = data.vehicles.first?.id
        save()
    }

    func startingOdometer(vehicleID: UUID, editing trip: TripRecord?) -> Double {
        let current = data.vehicles.first(where: { $0.id == vehicleID })?.odometer ?? 0
        // Editing must reuse the record's starting reading, not today's reading.
        guard let trip else { return current }
        return (trip.odometer ?? current) - trip.distance
    }

    func addTrip(_ trip: TripRecord) {
        data.trips.append(trip)
        if let odometer = trip.odometer, let index = data.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) {
            data.vehicles[index].odometer = max(data.vehicles[index].odometer, odometer)
        } else if let index = data.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) {
            data.vehicles[index].odometer += trip.distance
        }
        save()
    }

    func updateTrip(_ trip: TripRecord) {
        guard let index = data.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        let previous = data.trips[index]
        data.trips[index] = trip
        if let vehicleIndex = data.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) {
            if let odometer = trip.odometer {
                let current = data.vehicles[vehicleIndex].odometer
                if previous.odometer == current {
                    let otherReadings = data.trips.filter { $0.vehicleID == trip.vehicleID && $0.id != trip.id }.compactMap(\.odometer)
                        + data.fuels.filter { $0.vehicleID == trip.vehicleID }.map(\.odometer)
                    data.vehicles[vehicleIndex].odometer = max(odometer, otherReadings.max() ?? odometer)
                } else {
                    data.vehicles[vehicleIndex].odometer = max(current, odometer)
                }
            } else if previous.odometer == nil {
                data.vehicles[vehicleIndex].odometer = max(0, data.vehicles[vehicleIndex].odometer + trip.distance - previous.distance)
            }
        }
        save()
    }

    func deleteTrip(id: UUID) { data.trips.removeAll { $0.id == id }; save() }

    func addFuel(_ fuel: FuelRecord) {
        data.fuels.append(fuel)
        if let index = data.vehicles.firstIndex(where: { $0.id == fuel.vehicleID }) {
            data.vehicles[index].odometer = max(data.vehicles[index].odometer, fuel.odometer)
        }
        save()
    }

    func updateFuel(_ fuel: FuelRecord) {
        guard let index = data.fuels.firstIndex(where: { $0.id == fuel.id }) else { return }
        data.fuels[index] = fuel
        save()
    }

    func deleteFuel(id: UUID) { data.fuels.removeAll { $0.id == id }; save() }

    func updateNotificationSettings(_ settings: NotificationSettings) {
        data.notificationSettings = settings
        save()
        if settings.enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func setWeekStartsMonday(_ value: Bool) { data.weekStartsMonday = value; save() }
    func setAppearanceMode(_ value: AppAppearance) { data.appearanceMode = value; save() }

    func totalDistance(vehicleID: UUID, interval: DateInterval? = nil) -> Double {
        data.trips.lazy
            .filter { $0.vehicleID == vehicleID && (interval?.contains($0.date) ?? true) }
            .reduce(0) { $0 + $1.distance }
    }

    func fuelEfficiency(for record: FuelRecord) -> Double? {
        guard record.isFull else { return nil }
        let previous = data.fuels.lazy
            .filter { $0.isFull && $0.date < record.date }
            .filter { $0.vehicleID == record.vehicleID }
            .max { $0.date < $1.date }
        guard let previous, record.odometer > previous.odometer, record.liters > 0 else { return nil }
        let partials = data.fuels.filter {
            $0.vehicleID == record.vehicleID && $0.id != record.id
                && $0.date > previous.date && $0.date < record.date
        }
        guard partials.allSatisfy({ $0.liters > 0 }) else { return nil }
        let liters = record.liters + partials.reduce(0) { $0 + $1.liters }
        return (record.odometer - previous.odometer) / liters
    }

    func averageFuelEfficiency(vehicleID: UUID) -> Double? {
        averageFuelEfficiency(for: fuels(for: vehicleID))
    }

    func averageFuelEfficiency(for records: [FuelRecord]) -> Double? {
        let values = records.compactMap(fuelEfficiency)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    func exportURL() throws -> URL {
        var backup = data
        var photos: [String: Data] = [:]
        for vehicle in data.vehicles {
            guard let filename = vehicle.photoFilename else { continue }
            guard Self.isPhotoFilename(filename) else { throw BackupError.invalidPhoto }
            photos[filename] = try Data(contentsOf: photoDirectoryURL.appendingPathComponent(filename))
        }
        backup.vehiclePhotos = photos
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarLog-backup-\(UUID().uuidString).json")
        try encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }

    func restore(from url: URL) throws {
        let raw = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var restored = try decoder.decode(AppData.self, from: raw)
        var stagedPhotos: [URL] = []
        do {
            for index in restored.vehicles.indices {
                guard let filename = restored.vehicles[index].photoFilename else { continue }
                guard Self.isPhotoFilename(filename) else { throw BackupError.invalidPhoto }
                if let photos = restored.vehiclePhotos {
                    guard let bytes = photos[filename], UIImage(data: bytes) != nil else { throw BackupError.invalidPhoto }
                    // New filenames avoid overwriting photos belonging to current data.
                    let newFilename = "vehicle-\(UUID().uuidString).jpg"
                    let destination = photoDirectoryURL.appendingPathComponent(newFilename)
                    try FileManager.default.createDirectory(at: photoDirectoryURL, withIntermediateDirectories: true)
                    stagedPhotos.append(destination)
                    try bytes.write(to: destination, options: .atomic)
                    restored.vehicles[index].photoFilename = newFilename
                } else if !FileManager.default.fileExists(atPath: photoDirectoryURL.appendingPathComponent(filename).path) {
                    // Legacy JSON has no photo bytes. Keep a local photo when available.
                    restored.vehicles[index].photoFilename = nil
                }
            }
            restored.vehiclePhotos = nil
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(restored).write(to: fileURL, options: .atomic)
        } catch {
            for photo in stagedPhotos { try? FileManager.default.removeItem(at: photo) }
            throw error
        }
        data = restored
        selectedVehicleID = restored.vehicles.first(where: \.isPrimary)?.id ?? restored.vehicles.first?.id
    }

    private enum BackupError: Error { case invalidPhoto }

    private static func isPhotoFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".."
            && !filename.contains("/") && !filename.contains("\\")
    }

    private func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { data = try decoder.decode(AppData.self, from: raw) }
        catch { lastError = "保存データを読み込めませんでした。" }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do { try encoder.encode(data).write(to: fileURL, options: .atomic) }
        catch { lastError = "データを保存できませんでした。" }
        objectWillChange.send()
    }
}
