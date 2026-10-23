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
    var allowsEditing = true
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(source.uiSource) ? source.uiSource : .photoLibrary
        picker.allowsEditing = allowsEditing
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

enum MeterReadingKind: String {
    case odometer = "ODO"
    case tripA = "TRIP A"
    case tripB = "TRIP B"
    case trip = "TRIP"
    case unclassified = "種類不明"

    func matches(expectsOdometer: Bool) -> Bool {
        expectsOdometer ? self == .odometer : (self == .tripA || self == .tripB || self == .trip)
    }
}

struct MeterReading: Identifiable {
    let id = UUID()
    let kind: MeterReadingKind
    let value: Double
}

struct MeterTextFragment {
    let text: String
    // Vision coordinates: normalized to the image, with the origin at bottom left.
    let boundingBox: CGRect
}

struct MeterScanResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let readings: [MeterReading]
    let recognizedText: String

    var odometer: Double? { readings.first { $0.kind == .odometer }?.value }
    var tripValue: Double? { readings.first { $0.kind.matches(expectsOdometer: false) }?.value }

    func suggestedReading(expectsOdometer: Bool) -> MeterReading? {
        let matching = readings.filter { $0.kind.matches(expectsOdometer: expectsOdometer) }
        return matching.count == 1 ? matching[0] : nil
    }
}

// Kept separate from Vision so layouts and ambiguous matches can be regression-tested.
enum MeterReadingParser {
    static func fragments(in text: String, bounds: (Range<String.Index>) -> CGRect) -> [MeterTextFragment] {
        let pattern = #"(?i)(?<![A-Z])[O0]D[O0](?:METER)?(?![A-Z])|(?<![A-Z])TR[I1]P(?:\s*[AB])?(?![A-Z])|(?<![A-Z0-9])[AB](?![A-Z0-9])|\d+(?:,\d{3})*(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range])
            if Double(token.replacingOccurrences(of: ",", with: "")) != nil {
                let suffix = String(text[range.upperBound...])
                let prefix = String(text[..<range.lowerBound])
                // Speed, consumption, temperature and clock readings are not mileage.
                if suffix.range(of: #"^\s*(?:KM\s*/\s*[HL]|MPH|RPM|MPG|MILES?\b|MI\b|[°℃℉%:]|L\s*/\s*100)"#, options: [.regularExpression, .caseInsensitive]) != nil
                    || prefix.range(of: #":\s*$"#, options: .regularExpression) != nil { return nil }
            }
            return MeterTextFragment(text: token, boundingBox: bounds(range))
        }
    }

    private static func kind(_ text: String) -> MeterReadingKind? {
        let value = text.uppercased().filter { !$0.isWhitespace }
        if ["ODO", "ODOMETER"].contains(value.replacingOccurrences(of: "0", with: "O")) { return .odometer }
        if value == "TRIPA" || value == "TR1PA" { return .tripA }
        if value == "TRIPB" || value == "TR1PB" { return .tripB }
        if value == "TRIP" || value == "TR1P" { return .trip }
        return nil
    }

    private static func score(_ label: CGRect, _ number: CGRect) -> CGFloat? {
        let height = max(max(label.height, number.height), 0.01)
        let vertical = abs(label.midY - number.midY)
        let horizontalGap = max(0, max(label.minX - number.maxX, number.minX - label.maxX))
        if vertical <= height * 0.6, horizontalGap <= 0.4 {
            return vertical / height * 2 + horizontalGap / height
        }
        let verticalGap = max(0, max(label.minY - number.maxY, number.minY - label.maxY))
        let overlap = min(label.maxX, number.maxX) - max(label.minX, number.minX)
        if verticalGap <= max(0.04, height * 2), overlap > min(label.width, number.width) * 0.3 {
            return 2 + verticalGap / height + abs(label.midX - number.midX) / height
        }
        return nil
    }

    private static func uniqueBest(_ scores: [(index: Int, score: CGFloat)]) -> Int? {
        let ranked = scores.sorted { $0.score < $1.score }
        guard let first = ranked.first else { return nil }
        // Similar alternatives require an explicit choice; don't guess the category.
        if ranked.count > 1, ranked[1].score - first.score < 0.35 { return nil }
        return first.index
    }

    static func readings(from fragments: [MeterTextFragment]) -> [MeterReading] {
        var labels = fragments.compactMap { fragment -> (kind: MeterReadingKind, box: CGRect)? in
            guard let readingKind = kind(fragment.text) else { return nil }
            return (readingKind, fragment.boundingBox)
        }
        // Some displays produce three separate observations: TRIP, A/B, and digits.
        for index in labels.indices where labels[index].kind == .trip {
            let letters = fragments.filter { ["A", "B"].contains($0.text.uppercased()) }
            let scores = letters.enumerated().compactMap { offset, letter -> (index: Int, score: CGFloat)? in
                guard let distanceScore = score(labels[index].box, letter.boundingBox), distanceScore < 2 else { return nil }
                return (offset, distanceScore)
            }
            if let match = uniqueBest(scores) {
                labels[index].kind = letters[match].text.uppercased() == "A" ? .tripA : .tripB
                labels[index].box = labels[index].box.union(letters[match].boundingBox)
            }
        }
        let numbers = fragments.compactMap { fragment -> (value: Double, box: CGRect)? in
            guard let value = Double(fragment.text.replacingOccurrences(of: ",", with: "")), value.isFinite, value >= 0 else { return nil }
            return (value, fragment.boundingBox)
        }
        let labelChoices = labels.map { label in
            uniqueBest(numbers.enumerated().compactMap { index, number in
                score(label.box, number.box).map { (index: index, score: $0) }
            })
        }
        var readings: [MeterReading] = []
        for (index, number) in numbers.enumerated() {
            let labelIndex = uniqueBest(labels.enumerated().compactMap { index, label in
                score(label.box, number.box).map { (index: index, score: $0) }
            })
            let kind: MeterReadingKind
            if let labelIndex, labelChoices[labelIndex] == index { kind = labels[labelIndex].kind }
            else { kind = .unclassified }
            if !readings.contains(where: { $0.kind == kind && $0.value == number.value }) {
                readings.append(MeterReading(kind: kind, value: number.value))
            }
        }
        return readings
    }
}

enum MeterOCRService {
    static func recognize(_ image: UIImage) async throws -> MeterScanResult {
        guard let cgImage = image.cgImage else { throw RecognitionError.invalidImage }
        let orientation = image.cgOrientation
        let content: (fragments: [MeterTextFragment], text: String) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US", "ja-JP"]
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                    var fragments: [MeterTextFragment] = []
                    var lines: [String] = []
                    for observation in request.results ?? [] {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        lines.append(candidate.string)
                        fragments += MeterReadingParser.fragments(in: candidate.string) { range in
                            (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                        }
                    }
                    continuation.resume(returning: (fragments, lines.joined(separator: "\n")))
                } catch { continuation.resume(throwing: error) }
            }
        }
        return MeterScanResult(image: image, readings: MeterReadingParser.readings(from: content.fragments), recognizedText: content.text)
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
