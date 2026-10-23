import Foundation
import SwiftUI

enum BodyType: String, Codable, CaseIterable, Identifiable {
    case kei = "軽自動車"
    case compact = "コンパクト"
    case sedan = "セダン"
    case wagon = "ワゴン"
    case suv = "SUV"
    case minivan = "ミニバン"
    case sport = "クーペ／スポーツ"
    case utility = "バン／ピックアップ"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .kei, .compact: "car.side"
        case .sedan: "car.side.fill"
        case .wagon, .minivan: "bus"
        case .suv: "suv.side.fill"
        case .sport: "car.top.radiowaves.rear.left.and.rear.right"
        case .utility: "truck.box"
        }
    }
}

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case regular = "レギュラー"
    case premium = "ハイオク"
    case diesel = "軽油"
    case electric = "電気"
    case other = "その他"
    var id: String { rawValue }
}

enum AppMood: String, Codable, CaseIterable, Identifiable {
    case standard = "スタンダード"
    case cool = "クール"
    case cute = "キュート"
    var id: String { rawValue }

    var cornerRadius: CGFloat {
        switch self { case .standard: 20; case .cool: 12; case .cute: 28 }
    }
}

struct Vehicle: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var nickname: String
    var bodyType: BodyType
    var fuelType: FuelType
    var odometer: Double
    var primaryColorHex: String
    var secondaryColorHex: String?
    var mood: AppMood
    var isPrimary: Bool
    var createdAt = Date()
    var photoFilename: String? = nil
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system = "システム"
    case light = "デフォルト"
    case dark = "ナイトモード"

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TripInputMode: String, Codable, CaseIterable, Identifiable {
    case distance = "走った距離"
    case odometer = "オドメーター"
    case tripMeter = "トリップメーター"
    var id: String { rawValue }
    var displayName: String { self == .distance ? "手動入力" : rawValue }
}

struct TripRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var vehicleID: UUID
    var date: Date
    var distance: Double
    var odometer: Double?
    var mode: TripInputMode
    var purpose: String
    var note: String
}

struct FuelRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var vehicleID: UUID
    var date: Date
    var liters: Double
    var totalPrice: Double
    var odometer: Double
    var isFull: Bool
    var station: String
    var note: String

    var unitPrice: Double { liters > 0 ? totalPrice / liters : 0 }
}

struct NotificationSettings: Codable, Hashable {
    var enabled = false
    var locationName = "自宅"
    var radiusMeters = 200.0
    var carPlayOnly = true
}

struct AppData: Codable {
    var vehicles: [Vehicle] = []
    var trips: [TripRecord] = []
    var fuels: [FuelRecord] = []
    var notificationSettings = NotificationSettings()
    var weekStartsMonday = true
    var appearanceMode: AppAppearance?
    // Backups embed image bytes; ordinary app storage keeps filenames only.
    var vehiclePhotos: [String: Data]?
}

enum RecordItem: Identifiable {
    case trip(TripRecord)
    case fuel(FuelRecord)

    var id: UUID {
        switch self { case .trip(let value): value.id; case .fuel(let value): value.id }
    }
    var date: Date {
        switch self { case .trip(let value): value.date; case .fuel(let value): value.date }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: UInt64
        if cleaned.count == 3 {
            (red, green, blue) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        } else {
            (red, green, blue) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    func hexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "007AFF" }
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
