import SwiftUI

enum CarLogStyle {
    static let blue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.61, blue: 1.00, alpha: 1)
            : UIColor(red: 0.09, green: 0.49, blue: 0.95, alpha: 1)
    })
    static let deepBlue = Color(uiColor: .label)
    static let label = Color(uiColor: .secondaryLabel)
    static let border = Color(uiColor: .separator).opacity(0.65)
    static let softBlue = Color(uiColor: .tertiarySystemFill)
    static let segment = Color(uiColor: .secondarySystemFill)
}

struct CarLogTheme: Equatable {
    let mood: AppMood
    let colorScheme: ColorScheme

    init(mood: AppMood, colorScheme: ColorScheme = .light) {
        self.mood = mood
        self.colorScheme = colorScheme
    }

    var accent: Color {
        switch mood {
        case .standard: Color(hex: colorScheme == .dark ? "409CFF" : "167CF3")
        case .cool: Color(hex: colorScheme == .dark ? "35A7B8" : "176B87")
        case .cute: Color(hex: colorScheme == .dark ? "F07FA1" : "E96C91")
        }
    }

    var deepAccent: Color {
        switch mood {
        case .standard: Color(hex: colorScheme == .dark ? "B8D8FF" : "12356B")
        case .cool: Color(hex: colorScheme == .dark ? "BCEAF0" : "123E52")
        case .cute: Color(hex: colorScheme == .dark ? "FFD0DF" : "75334A")
        }
    }

    var softAccent: Color {
        switch mood {
        case .standard: Color(hex: colorScheme == .dark ? "162A42" : "EAF4FF")
        case .cool: Color(hex: colorScheme == .dark ? "153238" : "E7F3F5")
        case .cute: Color(hex: colorScheme == .dark ? "3A202B" : "FFF0F5")
        }
    }

    var secondaryGlow: Color {
        switch mood {
        case .standard: .cyan
        case .cool: .teal
        case .cute: Color(hex: "FFB38A")
        }
    }

    var cardRadius: CGFloat { mood.cornerRadius }
    var controlRadius: CGFloat { mood == .cool ? 8 : mood == .cute ? 18 : 12 }
    var thumbnailRadius: CGFloat { mood == .cool ? 9 : mood == .cute ? 20 : 13 }
}

private struct CarLogThemeKey: EnvironmentKey {
    static let defaultValue = CarLogTheme(mood: .standard)
}

extension EnvironmentValues {
    var carLogTheme: CarLogTheme {
        get { self[CarLogThemeKey.self] }
        set { self[CarLogThemeKey.self] = newValue }
    }
}

struct ScreenBackground: View {
    @Environment(\.carLogTheme) private var theme
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(colors: [theme.secondaryGlow.opacity(theme.mood == .cute ? 0.13 : 0.08), .clear], center: .topTrailing, startRadius: 30, endRadius: 500)
            RadialGradient(colors: [theme.accent.opacity(theme.mood == .cute ? 0.09 : 0.05), .clear], center: .bottomLeading, startRadius: 30, endRadius: 460)
        }.ignoresSafeArea()
    }
}

private struct CarLogCardModifier: ViewModifier {
    @Environment(\.carLogTheme) private var theme
    let padding: CGFloat
    let radius: CGFloat?

    func body(content: Content) -> some View {
        let resolvedRadius = radius ?? theme.cardRadius
        content.padding(padding)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.96), in: RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous).stroke(theme.accent.opacity(theme.mood == .standard ? 0.16 : 0.23), lineWidth: 1))
            .shadow(color: theme.accent.opacity(theme.mood == .cute ? 0.08 : 0.045), radius: theme.mood == .cute ? 14 : 10, y: 4)
    }
}

extension View {
    func carLogCard(padding: CGFloat = 16, radius: CGFloat? = nil) -> some View {
        modifier(CarLogCardModifier(padding: padding, radius: radius))
    }

    func screenTitleStyle() -> some View {
        self.font(.system(size: 36, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VehicleThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let vehicle: Vehicle
    var size: CGFloat = 62
    var body: some View {
        let theme = CarLogTheme(mood: vehicle.mood, colorScheme: colorScheme)
        ZStack {
            RoundedRectangle(cornerRadius: theme.thumbnailRadius, style: .continuous)
                .fill(LinearGradient(colors: [theme.softAccent, Color(hex: vehicle.primaryColorHex).opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let photo = AppStore.vehiclePhoto(filename: vehicle.photoFilename) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Image(systemName: vehicle.bodyType.symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Color(hex: vehicle.primaryColorHex))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: theme.thumbnailRadius, style: .continuous))
    }
}

struct VehicleSummaryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let vehicle: Vehicle
    var showsOdometer = false
    var showsChevron = true
    var body: some View {
        let theme = CarLogTheme(mood: vehicle.mood, colorScheme: colorScheme)
        HStack(spacing: 14) {
            VehicleThumbnail(vehicle: vehicle)
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.nickname.isEmpty ? vehicle.name : vehicle.nickname).font(.title3.bold()).foregroundStyle(.primary)
                Text(showsOdometer ? vehicle.odometer.formatted(.number.precision(.fractionLength(0))) + " Km" : (vehicle.isPrimary ? "メイン車両" : vehicle.name))
                    .font(.subheadline).foregroundStyle(CarLogStyle.label)
            }
            Spacer()
            if showsChevron { Image(systemName: "chevron.right").font(.headline).foregroundStyle(theme.deepAccent) }
        }
    }
}

struct MetricCard: View {
    @Environment(\.carLogTheme) private var theme
    let title: String
    let value: String
    var symbol: String? = nil
    var accent: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(title).font(.subheadline).foregroundStyle(CarLogStyle.label); Spacer(); if let symbol { Image(systemName: symbol).foregroundStyle(accent ?? theme.accent) } }
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).minimumScaleFactor(0.62).lineLimit(1)
        }.carLogCard(padding: 14)
    }
}

struct CarLogSegmentedPicker: View {
    @Environment(\.carLogTheme) private var theme
    let labels: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Button { withAnimation(.snappy) { selection = index } } label: {
                    Text(labels[index]).font(.headline).foregroundStyle(selection == index ? .white : theme.deepAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(selection == index ? theme.accent : .clear, in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
                }.buttonStyle(.plain)
            }
        }.padding(3).background(CarLogStyle.segment, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MonthNavigator: View {
    @Environment(\.carLogTheme) private var theme
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").monthButton(theme: theme) }
            Spacer(); Text(month, format: .dateTime.year().month()).font(.title2.bold()); Spacer()
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").monthButton(theme: theme) }
        }
    }
}

private extension View {
    func monthButton(theme: CarLogTheme) -> some View { self.font(.headline).foregroundStyle(theme.deepAccent).frame(width: 42, height: 42).background(theme.softAccent, in: Circle()) }
}

struct PrimaryActionButton: View {
    @Environment(\.carLogTheme) private var theme
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(theme.accent, in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)) }.buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) }
}

struct LabeledNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(CarLogStyle.label)
            HStack(alignment: .firstTextBaseline) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).font(.system(size: 32, weight: .bold, design: .rounded))
                Text(unit).font(.title3).foregroundStyle(CarLogStyle.label)
            }
        }
    }
}

extension Date {
    var startOfMonth: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))! }
    var monthInterval: DateInterval { Calendar.current.dateInterval(of: .month, for: self)! }
}
