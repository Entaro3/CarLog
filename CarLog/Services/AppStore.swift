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
        value.initialOdometer = value.initialOdometer ?? value.odometer
        if data.vehicles.isEmpty { value.isPrimary = true }
        let saved = commit { candidate in
            if value.isPrimary { candidate.vehicles.indices.forEach { candidate.vehicles[$0].isPrimary = false } }
            candidate.vehicles.append(value)
        }
        if saved { selectedVehicleID = value.id }
        return saved
    }

    @discardableResult
    func updateVehicle(_ vehicle: Vehicle, correctedOdometer: Double? = nil, correctionDate: Date = Date()) -> Bool {
        guard let index = data.vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return false }
        return commit { candidate in
            var value = vehicle
            value.initialOdometer = value.initialOdometer ?? candidate.vehicles[index].initialOdometer
            value.odometerCorrections = candidate.vehicles[index].odometerCorrections
            if let correctedOdometer {
                value.odometerCorrections = (value.odometerCorrections ?? []) + [
                    OdometerCorrection(date: correctionDate, odometer: correctedOdometer)
                ]
            }
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
        commit { $0.trips.append(trip) }
    }

    @discardableResult
    func updateTrip(_ trip: TripRecord) -> Bool {
        guard let index = data.trips.firstIndex(where: { $0.id == trip.id }) else { return false }
        return commit { $0.trips[index] = trip }
    }

    @discardableResult
    func deleteTrip(id: UUID) -> Bool {
        commit { $0.trips.removeAll { $0.id == id } }
    }

    // Replacing a same-day record (including an edited record) is one transaction.
    @discardableResult
    func replaceTrip(_ trip: TripRecord, removing id: UUID?) -> Bool {
        commit { candidate in
            if let id, id != trip.id { candidate.trips.removeAll { $0.id == id } }
            if let index = candidate.trips.firstIndex(where: { $0.id == trip.id }) {
                candidate.trips[index] = trip
            } else {
                candidate.trips.append(trip)
            }
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

    @discardableResult
    func updateOdometerCorrection(vehicleID: UUID, correction: OdometerCorrection) -> Bool {
        guard let vehicleIndex = data.vehicles.firstIndex(where: { $0.id == vehicleID }),
              let correctionIndex = data.vehicles[vehicleIndex].odometerCorrections?.firstIndex(where: { $0.id == correction.id }) else { return false }
        return commit { $0.vehicles[vehicleIndex].odometerCorrections?[correctionIndex] = correction }
    }

    @discardableResult
    func deleteOdometerCorrection(vehicleID: UUID, id: UUID) -> Bool {
        guard let index = data.vehicles.firstIndex(where: { $0.id == vehicleID }) else { return false }
        return commit { $0.vehicles[index].odometerCorrections?.removeAll { $0.id == id } }
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
        try Self.recalculateMileage(in: &restored)
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

    private struct MileageEvent {
        let id: UUID
        let date: Date
        let tripIndex: Int?
        let odometer: Double?
        let distance: Double
        var isCorrection = false

        static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.isCorrection != rhs.isCorrection { return !lhs.isCorrection }
            // Date-only imports may share a timestamp. Count manual distances first,
            // then readings in increasing order, with trips before fuel at equal ODO.
            if (lhs.odometer == nil) != (rhs.odometer == nil) { return lhs.odometer == nil }
            if let left = lhs.odometer, let right = rhs.odometer, left != right { return left < right }
            if (lhs.tripIndex == nil) != (rhs.tripIndex == nil) { return lhs.tripIndex != nil }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func recalculateMileage(in candidate: inout AppData) throws {
        let vehicleIDs = Set(candidate.vehicles.map(\.id))
        guard candidate.trips.allSatisfy({ vehicleIDs.contains($0.vehicleID) }),
              candidate.fuels.allSatisfy({ vehicleIDs.contains($0.vehicleID) }) else {
            throw MileageError("車両が存在しない記録があります。車両と記録を確認してください。")
        }
        for vehicleIndex in candidate.vehicles.indices {
            let vehicle = candidate.vehicles[vehicleIndex]
            let tripIndices = candidate.trips.indices.filter { candidate.trips[$0].vehicleID == vehicle.id }
            let fuels = candidate.fuels.filter { $0.vehicleID == vehicle.id }
            var events = tripIndices.map { index in
                let trip = candidate.trips[index]
                return MileageEvent(id: trip.id, date: trip.date, tripIndex: index,
                                    odometer: trip.odometer, distance: trip.distance)
            }
            // Older app versions allowed saving a fuel entry without an ODO (zero).
            // Such entries still count towards fuel costs but cannot anchor mileage.
            events += fuels.filter { $0.odometer > 0 }.map {
                MileageEvent(id: $0.id, date: $0.date, tripIndex: nil, odometer: $0.odometer, distance: 0)
            }
            events += (vehicle.odometerCorrections ?? []).map {
                MileageEvent(id: $0.id, date: $0.date, tripIndex: nil, odometer: $0.odometer, distance: 0, isCorrection: true)
            }
            events.sort(by: MileageEvent.precedes)

            if vehicle.initialOdometer == nil {
                // Older JSON did not retain the registration reading. Infer it once
                // from the first ODO trip's saved start, bounded by earlier fuel ODOs.
                var manualDistance = 0.0
                var inferred: Double?
                var firstFuelStart: Double?
                for event in events {
                    if let reading = event.odometer {
                        if event.tripIndex != nil {
                            inferred = reading - event.distance - manualDistance
                            break
                        }
                        if firstFuelStart == nil { firstFuelStart = reading - manualDistance }
                    } else {
                        manualDistance += event.distance
                    }
                }
                let fallback = firstFuelStart ?? (vehicle.odometer - manualDistance)
                candidate.vehicles[vehicleIndex].initialOdometer = max(0, min(inferred ?? fallback, firstFuelStart ?? inferred ?? fallback))
            }
            guard let initial = candidate.vehicles[vehicleIndex].initialOdometer,
                  initial.isFinite, initial >= 0 else {
                throw MileageError("\(vehicle.name)の登録時ODOは0以上の数値を入力してください。")
            }
            guard fuels.allSatisfy({ $0.odometer.isFinite && $0.odometer >= 0 }) else {
                throw MileageError("給油記録のODOは0以上の数値を入力してください。")
            }
            var tripOdometer = initial
            var vehicleOdometer = initial
            var lastMeasuredOdometer = initial
            for event in events {
                if let reading = event.odometer {
                    // Avoid rejecting decimal input because 0.1 + 0.2 is not exactly 0.3.
                    let tolerance = 0.000001
                    if event.isCorrection {
                        guard reading.isFinite, reading >= 0, reading + tolerance >= lastMeasuredOdometer else {
                            throw MileageError("ODO補正が以前の実測ODOより小さくなります。誤った走行・給油記録や補正履歴を先に修正してください。")
                        }
                        // An explicit correction can reduce drift from manual estimates.
                        // It does not rewrite past manual entries or create a trip.
                        if let index = candidate.vehicles[vehicleIndex].odometerCorrections?.firstIndex(where: { $0.id == event.id }) {
                            candidate.vehicles[vehicleIndex].odometerCorrections?[index].previousOdometer = vehicleOdometer
                        }
                        tripOdometer = reading
                        vehicleOdometer = reading
                        lastMeasuredOdometer = reading
                        continue
                    }
                    guard reading.isFinite, reading >= 0, reading + tolerance >= vehicleOdometer,
                          event.tripIndex == nil || reading + tolerance >= tripOdometer else {
                        throw MileageError("\(vehicle.name)のODOが前の記録より小さくなります。記録日時、ODO、走行距離を確認してください。")
                    }
                    if let index = event.tripIndex {
                        // Fuel ODOs anchor the vehicle display, but do not consume
                        // unrecorded travel from the next trip's distance.
                        candidate.trips[index].distance = max(0, reading - tripOdometer)
                        tripOdometer = reading
                    }
                    vehicleOdometer = reading
                    lastMeasuredOdometer = reading
                } else {
                    guard event.distance.isFinite, event.distance > 0 else {
                        throw MileageError("走行距離は0より大きい数値を入力してください。")
                    }
                    tripOdometer += event.distance
                    vehicleOdometer += event.distance
                    guard tripOdometer.isFinite, vehicleOdometer.isFinite else {
                        throw MileageError("走行距離が大きすぎます。入力内容を確認してください。")
                    }
                }
            }
            candidate.vehicles[vehicleIndex].odometer = vehicleOdometer
        }
    }

    private func commit(_ change: (inout AppData) -> Void) -> Bool {
        var candidate = data
        do {
            // Freeze legacy baselines before editing/deleting the evidence used to infer them.
            // Load/restore normally migrate already; this also handles loaded invalid history.
            Self.migrateBaselines(in: &candidate)
            change(&candidate)
            try Self.recalculateMileage(in: &candidate)
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

    private static func migrateBaselines(in candidate: inout AppData) {
        guard candidate.vehicles.contains(where: { $0.initialOdometer == nil }) else { return }
        var migrated = candidate
        // Even if old history is contradictory, preserve any inferred baselines
        // while leaving original entries intact for the user to correct.
        try? recalculateMileage(in: &migrated)
        for index in candidate.vehicles.indices where candidate.vehicles[index].initialOdometer == nil {
            candidate.vehicles[index].initialOdometer = migrated.vehicles[index].initialOdometer
        }
    }

    private func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            data = try decoder.decode(AppData.self, from: raw)
            var recalculated = data
            do {
                try Self.recalculateMileage(in: &recalculated)
                data = recalculated
                save()
            } catch {
                Self.migrateBaselines(in: &data)
                lastError = error.localizedDescription
            }
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
