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

    @discardableResult
    func addVehicle(_ vehicle: Vehicle) -> Bool {
        var value = vehicle
        if data.vehicles.isEmpty { value.isPrimary = true }
        let saved = commit { candidate in
            if value.isPrimary { candidate.vehicles.indices.forEach { candidate.vehicles[$0].isPrimary = false } }
            candidate.vehicles.append(value)
        }
        if saved { selectedVehicleID = value.id }
        return saved
    }

    @discardableResult
    func updateVehicle(_ vehicle: Vehicle) -> Bool {
        guard let index = data.vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return false }
        return commit { candidate in
            var value = vehicle
            // Retain metadata from older backups without using it to recalculate mileage.
            value.initialOdometer = candidate.vehicles[index].initialOdometer
            value.odometerCorrections = candidate.vehicles[index].odometerCorrections
            if value.isPrimary { candidate.vehicles.indices.forEach { candidate.vehicles[$0].isPrimary = false } }
            candidate.vehicles[index] = value
        }
    }

    @discardableResult
    func deleteVehicle(_ vehicle: Vehicle) -> Bool {
        let saved = commit { candidate in
            candidate.vehicles.removeAll { $0.id == vehicle.id }
            candidate.trips.removeAll { $0.vehicleID == vehicle.id }
            candidate.fuels.removeAll { $0.vehicleID == vehicle.id }
            if !candidate.vehicles.contains(where: \.isPrimary), !candidate.vehicles.isEmpty {
                candidate.vehicles[0].isPrimary = true
            }
        }
        if saved {
            if let filename = vehicle.photoFilename { try? FileManager.default.removeItem(at: photoDirectoryURL.appendingPathComponent(filename)) }
            selectedVehicleID = data.vehicles.first?.id
        }
        return saved
    }

    @discardableResult
    func addTrip(_ trip: TripRecord) -> Bool {
        commit { candidate in
            guard let index = candidate.vehicles.firstIndex(where: { $0.id == trip.vehicleID }),
                  !candidate.trips.contains(where: { $0.id == trip.id }) else {
                throw MileageError("車両または走行記録を確認してください。")
            }
            var value = trip
            if let reading = value.odometer {
                // Only a new ODO entry converts the vehicle's current reading to distance.
                value.distance = reading - candidate.vehicles[index].odometer
            }
            guard value.distance.isFinite, value.distance > 0 else {
                throw MileageError("走行距離は0より大きい数値を入力してください。ODO入力の場合は現在の車両ODOより大きい数値を入力してください。")
            }
            candidate.vehicles[index].odometer += value.distance
            candidate.trips.append(value)
        }
    }

    @discardableResult
    func updateTrip(_ trip: TripRecord) -> Bool {
        guard let index = data.trips.firstIndex(where: { $0.id == trip.id }) else { return false }
        return commit { candidate in
            let previous = candidate.trips[index]
            guard previous.vehicleID == trip.vehicleID,
                  let vehicleIndex = candidate.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) else {
                throw MileageError("走行記録の車両を確認してください。")
            }
            var value = trip
            // Editing changes distance; retain the ODO originally entered as reference.
            value.odometer = previous.odometer
            value.mode = previous.mode
            candidate.vehicles[vehicleIndex].odometer += value.distance - previous.distance
            candidate.trips[index] = value
        }
    }

    @discardableResult
    func deleteTrip(id: UUID) -> Bool {
        guard let trip = data.trips.first(where: { $0.id == id }) else { return false }
        return commit { candidate in
            guard let index = candidate.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) else {
                throw MileageError("走行記録の車両を確認してください。")
            }
            candidate.vehicles[index].odometer -= trip.distance
            candidate.trips.removeAll { $0.id == id }
        }
    }

    // A same-day overwrite applies the net distance change in one transaction.
    @discardableResult
    func replaceTrip(_ trip: TripRecord, removing id: UUID?) -> Bool {
        commit { candidate in
            guard let previous = candidate.trips.first(where: { $0.id == trip.id }),
                  previous.vehicleID == trip.vehicleID,
                  let index = candidate.vehicles.firstIndex(where: { $0.id == trip.vehicleID }) else {
                throw MileageError("上書きする走行記録を確認してください。")
            }
            var removedDistance = previous.distance
            if let id, id != trip.id {
                guard let edited = candidate.trips.first(where: { $0.id == id }), edited.vehicleID == trip.vehicleID else {
                    throw MileageError("編集する走行記録を確認してください。")
                }
                removedDistance += edited.distance
            }
            candidate.trips.removeAll { $0.id == trip.id || $0.id == id }
            candidate.trips.append(trip)
            candidate.vehicles[index].odometer += trip.distance - removedDistance
        }
    }

    @discardableResult
    func addFuel(_ fuel: FuelRecord) -> Bool {
        commit { $0.fuels.append(fuel) }
    }

    @discardableResult
    func updateFuel(_ fuel: FuelRecord) -> Bool {
        guard let index = data.fuels.firstIndex(where: { $0.id == fuel.id }) else { return false }
        return commit { $0.fuels[index] = fuel }
    }

    @discardableResult
    func deleteFuel(id: UUID) -> Bool {
        commit { $0.fuels.removeAll { $0.id == id } }
    }

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
        try Self.validateMileage(in: restored)
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

    private struct MileageError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func validateMileage(in candidate: AppData) throws {
        guard candidate.vehicles.allSatisfy({ $0.odometer.isFinite && $0.odometer >= 0 }) else {
            throw MileageError("車両ODOが不正、または0未満になります。記録の走行距離、または車両設定のODOを確認してください。")
        }
        let vehicleIDs = Set(candidate.vehicles.map(\.id))
        guard candidate.trips.allSatisfy({ vehicleIDs.contains($0.vehicleID) }),
              candidate.fuels.allSatisfy({ vehicleIDs.contains($0.vehicleID) }) else {
            throw MileageError("車両が存在しない記録があります。車両と記録を確認してください。")
        }
        guard candidate.trips.allSatisfy({
            $0.distance.isFinite && $0.distance >= 0
                && ($0.distance > 0 || $0.odometer != nil)
                && ($0.odometer.map { $0.isFinite && $0 >= 0 } ?? true)
        }) else {
            throw MileageError("走行距離とODOは有効な数値を入力してください。")
        }
        guard candidate.fuels.allSatisfy({ $0.odometer.isFinite && $0.odometer >= 0 }) else {
            throw MileageError("給油記録のODOは0以上の数値を入力してください。")
        }
    }

    private func commit(_ change: (inout AppData) throws -> Void) -> Bool {
        var candidate = data
        do {
            try change(&candidate)
            // Normalize tiny negative values caused only by floating-point subtraction.
            for index in candidate.vehicles.indices where candidate.vehicles[index].odometer < 0
                && candidate.vehicles[index].odometer >= -0.000000001 {
                candidate.vehicles[index].odometer = 0
            }
            try Self.validateMileage(in: candidate)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(candidate).write(to: fileURL, options: .atomic)
            data = candidate
            lastError = nil
            return true
        } catch {
            lastError = (error as? MileageError)?.localizedDescription ?? "データを保存できませんでした。入力内容や空き容量を確認してください。"
            return false
        }
    }

    private func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let loaded = try decoder.decode(AppData.self, from: raw)
            // Existing distances and current ODO are authoritative. Never replay history.
            data = loaded
        }
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
