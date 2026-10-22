import SwiftUI
import UIKit
@preconcurrency import Vision

enum ImagePickerSource {
    case camera
    case photoLibrary

    var uiSource: UIImagePickerController.SourceType {
        switch self { case .camera: .camera; case .photoLibrary: .photoLibrary }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let source: ImagePickerSource
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(source.uiSource) ? source.uiSource : .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct ReceiptScanResult: Identifiable {
    let id = UUID()
    let image: UIImage
    var date: Date
    var liters: Double
    var unitPrice: Double
    var totalPrice: Double
    var station: String
    var recognizedText: String
}

struct MeterScanResult: Identifiable {
    let id = UUID()
    let image: UIImage
    var odometer: Double?
    var tripA: Double?
    var tripB: Double?
    var recognizedText: String

    var tripValue: Double? { tripA ?? tripB }
    var tripLabel: String { tripA != nil ? "TRIP A" : tripB != nil ? "TRIP B" : "TRIP" }
}

enum MeterOCRService {
    static func recognize(_ image: UIImage) async throws -> MeterScanResult {
        guard let cgImage = image.cgImage else { throw RecognitionError.invalidImage }
        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "ja-JP"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
        let normalized = lines.map { $0.uppercased().replacingOccurrences(of: "O", with: "0", options: [], range: nil) }
        var odo: Double?
        var tripA: Double?
        var tripB: Double?
        for index in normalized.indices {
            let originalUpper = lines[index].uppercased()
            let end = min(lines.count, index + 4)
            let nearby = lines[index..<end].joined(separator: " ")
            if originalUpper.contains("ODO") || originalUpper.contains("ODOMETER") { odo = odo ?? meterNumber(in: nearby, after: ["ODOMETER", "ODO"]) }
            if originalUpper.contains("TRIP A") || originalUpper.replacingOccurrences(of: " ", with: "").contains("TRIPA") { tripA = tripA ?? meterNumber(in: nearby, after: ["TRIP A", "TRIPA"] ) }
            if originalUpper.contains("TRIP B") || originalUpper.replacingOccurrences(of: " ", with: "").contains("TRIPB") { tripB = tripB ?? meterNumber(in: nearby, after: ["TRIP B", "TRIPB"] ) }
            if originalUpper == "TRIP", index + 1 < lines.count {
                let next = lines[index + 1].uppercased()
                if next == "A" { tripA = tripA ?? firstMeterNumber(in: lines[index..<end].joined(separator: " ")) }
                if next == "B" { tripB = tripB ?? firstMeterNumber(in: lines[index..<end].joined(separator: " ")) }
            }
        }
        if odo == nil, tripA == nil, tripB == nil {
            let fallback = lines.compactMap(firstMeterNumber).first
            return MeterScanResult(image: image, odometer: nil, tripA: fallback, tripB: nil, recognizedText: lines.joined(separator: "\n"))
        }
        _ = normalized
        return MeterScanResult(image: image, odometer: odo, tripA: tripA, tripB: tripB, recognizedText: lines.joined(separator: "\n"))
    }

    private static func meterNumber(in text: String, after labels: [String]) -> Double? {
        var value = text.uppercased()
        for label in labels { value = value.replacingOccurrences(of: label, with: " ") }
        return firstMeterNumber(in: value)
    }

    private static func firstMeterNumber(in text: String) -> Double? {
        let pattern = #"(\d[\d,\s]*?(?:\.\d+)?)\s*(?:KM|KM/H|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let cleaned = text[range].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
            if let value = Double(cleaned), value >= 0 { return value }
        }
        return nil
    }

    enum RecognitionError: Error { case invalidImage }
}

enum ReceiptOCRService {
    static func recognize(_ image: UIImage) async throws -> ReceiptScanResult {
        guard let cgImage = image.cgImage else { throw RecognitionError.invalidImage }
        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let values = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: values)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ja-JP", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
        return parse(lines: lines, image: image)
    }

    private static func parse(lines: [String], image: UIImage) -> ReceiptScanResult {
        let normalized = lines.map { $0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "　", with: " ") }
        let fullText = normalized.joined(separator: "\n")
        let date = parseDate(fullText) ?? Date()
        let liters = firstNumber(in: normalized, patterns: [#"(\d{1,3}(?:\.\d{1,3})?)\s*[LＬ](?:\s|$)"#, #"給油量[^0-9]*(\d{1,3}(?:\.\d+)?)"#]) ?? 0
        var unitPrice = firstNumber(in: normalized, patterns: [#"[@＠]\s*[¥￥]?\s*(\d{2,3}(?:\.\d+)?)"#, #"単価[^0-9]*(\d{2,3}(?:\.\d+)?)"#, #"(\d{2,3}(?:\.\d+)?)\s*円?\s*/\s*[LＬ]"#]) ?? 0
        var total = firstNumber(in: normalized.filter { $0.contains("合計") || $0.contains("支払") || $0.contains("領収金額") }, patterns: [#"[¥￥]?\s*(\d{3,7})\s*円?"#]) ?? 0
        if total == 0 { total = firstNumber(in: normalized, patterns: [#"[¥￥]\s*(\d{3,7})"#]) ?? 0 }
        if unitPrice == 0, liters > 0, total > 0 { unitPrice = total / liters }
        if total == 0, liters > 0, unitPrice > 0 { total = liters * unitPrice }
        let station = parseStation(normalized)
        return ReceiptScanResult(image: image, date: date, liters: liters, unitPrice: unitPrice, totalPrice: total, station: station, recognizedText: fullText)
    }

    private static func firstNumber(in lines: [String], patterns: [String]) -> Double? {
        for line in lines {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: line) else { continue }
                if let value = Double(line[range]) { return value }
            }
        }
        return nil
    }

    private static func parseDate(_ text: String) -> Date? {
        let pattern = #"(20\d{2})\s*[年/\.\-]\s*(\d{1,2})\s*[月/\.\-]\s*(\d{1,2})\s*日?[^0-9]{0,8}(?:(\d{1,2})\s*:\s*(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func number(_ index: Int) -> Int? { guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return nil }; return Int(text[range]) }
        var components = DateComponents(); components.calendar = .current; components.timeZone = .current
        components.year = number(1); components.month = number(2); components.day = number(3); components.hour = number(4) ?? 12; components.minute = number(5) ?? 0
        return components.date
    }

    private static func parseStation(_ lines: [String]) -> String {
        let brands = ["ENEOS", "エネオス", "apollostation", "出光", "Shell", "シェル", "COSMO", "コスモ", "JA-SS", "キグナス", "SOLATO"]
        if let line = lines.first(where: { value in brands.contains { value.localizedCaseInsensitiveContains($0) } }) { return line.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let line = lines.first(where: { $0.localizedCaseInsensitiveContains("SS") || $0.contains("サービスステーション") || $0.contains("給油所") || $0.hasSuffix("店") }) { return line.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ""
    }

    enum RecognitionError: Error { case invalidImage }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up; case .down: .down; case .left: .left; case .right: .right
        case .upMirrored: .upMirrored; case .downMirrored: .downMirrored; case .leftMirrored: .leftMirrored; case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
