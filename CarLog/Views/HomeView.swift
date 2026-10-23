import Charts
import SwiftUI

enum HomeRecordDestination {
    case trip, fuel
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.carLogTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let openAnalytics: (Int) -> Void
    let openRecord: (HomeRecordDestination) -> Void
    @State private var displayedMonth = Date().startOfMonth
    @State private var selectedCalendarDate = Date()
    @State private var editingTrip: TripRecord?

    init(
        openAnalytics: @escaping (Int) -> Void = { _ in },
        openRecord: @escaping (HomeRecordDestination) -> Void = { _ in }
    ) {
        self.openAnalytics = openAnalytics
        self.openRecord = openRecord
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                if let vehicle = store.selectedVehicle {
                    VStack(spacing: 14) { header(vehicle); distanceCards(vehicle); recordCard; insightCards(vehicle); calendarCard(vehicle) }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: displayedMonth) { _, month in selectedCalendarDate = month }
        .sheet(item: $editingTrip) { trip in
            NavigationStack { TripEditorView(vehicleID: trip.vehicleID, existing: trip) }
        }
    }

    private func header(_ vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カーログ").screenTitleStyle().padding(.top, 10)
            HStack {
                Menu {
                    ForEach(store.data.vehicles) { item in Button(item.nickname.isEmpty ? item.name : item.nickname) { store.selectedVehicleID = item.id } }
                } label: {
                    HStack(spacing: 12) {
                        VehicleThumbnail(vehicle: vehicle, size: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(vehicle.nickname.isEmpty ? vehicle.name : vehicle.nickname).font(.headline).foregroundStyle(.primary); Image(systemName: "chevron.right").foregroundStyle(CarLogStyle.label) }
                            Text(vehicle.odometer.formatted(.number.precision(.fractionLength(0))) + " Km").foregroundStyle(CarLogStyle.label)
                        }
                    }
                }
                Spacer(); Text(Date(), format: .dateTime.year().month().day().weekday(.wide)).font(.subheadline).foregroundStyle(CarLogStyle.label)
            }
        }
    }

    private func distanceCards(_ vehicle: Vehicle) -> some View {
        var calendar = Calendar.current
        calendar.firstWeekday = store.data.weekStartsMonday ? 2 : 1
        return HStack(spacing: 10) {
            MetricCard(title: "今日", value: distance(vehicle.id, calendar.dateInterval(of: .day, for: Date())!), symbol: "car.fill")
            MetricCard(title: "今週", value: distance(vehicle.id, calendar.dateInterval(of: .weekOfYear, for: Date())!), symbol: "chart.bar.fill")
            MetricCard(title: "今月", value: distance(vehicle.id, calendar.dateInterval(of: .month, for: Date())!), symbol: "calendar")
        }
    }

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("記録する").font(.title3.bold())
            HStack(spacing: 10) {
                Button { openRecord(.trip) } label: { Label("走行距離", systemImage: "road.lanes").recordAction(filled: true, theme: theme) }
                Button { openRecord(.fuel) } label: { Label("給油", systemImage: "fuelpump.fill").recordAction(filled: true, theme: theme) }
            }.buttonStyle(.plain)
        }.carLogCard(padding: 12)
    }

    private func insightCards(_ vehicle: Vehicle) -> some View {
        let currentInterval = Date().monthInterval
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentInterval.start)!
        let previousInterval = previousMonth.monthInterval
        let allFuels = store.fuels(for: vehicle.id)
        let fuels = allFuels.filter { currentInterval.contains($0.date) }
        let previousFuels = allFuels.filter { previousInterval.contains($0.date) }
        return HStack(spacing: 10) {
            fuelEfficiencyCard(value: store.averageFuelEfficiency(vehicleID: vehicle.id).map { "\($0.formatted(.number.precision(.fractionLength(1)))) Km/L" } ?? "計算待ち", values: fuels.compactMap(store.fuelEfficiency))
            fuelCostCard(
                current: fuels.reduce(0) { $0 + $1.totalPrice },
                previous: previousFuels.reduce(0) { $0 + $1.totalPrice },
                count: fuels.count,
                hasPreviousData: !previousFuels.isEmpty
            )
        }
    }

    private func fuelEfficiencyCard(value: String, values: [Double]) -> some View {
        let scale = chartScale(values: values)
        return Button { openAnalytics(1) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Text("直近の燃費").font(.subheadline).foregroundStyle(CarLogStyle.label)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(theme.deepAccent)
                }
                Text(value).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.primary)
                Chart(Array(values.enumerated()), id: \.offset) { point in
                    LineMark(x: .value("順", point.offset), y: .value("値", point.element)).foregroundStyle(theme.accent)
                    PointMark(x: .value("順", point.offset), y: .value("値", point.element)).foregroundStyle(theme.accent)
                }
                .chartYScale(domain: scale.lowerBound...scale.upperBound)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: scale.marks) { axisValue in
                        AxisGridLine().foregroundStyle(CarLogStyle.border)
                        AxisTick().foregroundStyle(CarLogStyle.label)
                        AxisValueLabel {
                            if let number = axisValue.as(Double.self) {
                                Text(fuelAxisLabel(number, step: scale.step))
                                    .font(.system(size: 8, weight: .medium, design: .rounded))
                                    .foregroundStyle(CarLogStyle.label)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .frame(height: 76)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .carLogCard(padding: 12)
    }

    private func fuelCostCard(current: Double, previous: Double, count: Int, hasPreviousData: Bool) -> some View {
        Button { openAnalytics(2) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("今月のガソリン代").font(.subheadline).foregroundStyle(CarLogStyle.label)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(theme.deepAccent)
                }
                Text(current.formatted(.currency(code: "JPY").precision(.fractionLength(0))))
                    .font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(fuelCostComparison(current: current, previous: previous, hasPreviousData: hasPreviousData))
                    .font(.caption.bold()).foregroundStyle(hasPreviousData ? theme.deepAccent : CarLogStyle.label)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text("今月の給油 \(count)回")
                    .font(.caption).foregroundStyle(CarLogStyle.label)
                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 131, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .carLogCard(padding: 12)
    }

    private func fuelCostComparison(current: Double, previous: Double, hasPreviousData: Bool) -> String {
        guard hasPreviousData else { return "前月データなし" }
        let difference = current - previous
        if abs(difference) < 0.5 { return "前月と同額" }
        let amount = abs(difference).formatted(.currency(code: "JPY").precision(.fractionLength(0)))
        return difference < 0 ? "前月より \(amount)少ない" : "前月より \(amount)多い"
    }

    private func chartScale(values: [Double]) -> (lowerBound: Double, upperBound: Double, step: Double, marks: [Double]) {
        guard let minimum = values.min(), let maximum = values.max() else {
            return (8, 16, 2, [8, 10, 12, 14, 16])
        }
        let spread = maximum - minimum
        let padding = spread > 0.1 ? max(spread * 0.2, 0.5) : max(maximum * 0.1, 1)
        let proposedLower = max(0.1, minimum - padding)
        let proposedUpper = maximum + padding
        let rawStep = (proposedUpper - proposedLower) / 4
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let niceFactor: Double
        if normalized <= 1 { niceFactor = 1 }
        else if normalized <= 2 { niceFactor = 2 }
        else if normalized <= 5 { niceFactor = 5 }
        else { niceFactor = 10 }
        let step = niceFactor * magnitude
        let lowerBound = max(step, floor(proposedLower / step) * step)
        let upperBound = max(lowerBound + step, ceil(proposedUpper / step) * step)
        let count = Int(((upperBound - lowerBound) / step).rounded())
        return (lowerBound, upperBound, step, (0...count).map { lowerBound + Double($0) * step })
    }

    private func fuelAxisLabel(_ value: Double, step: Double) -> String {
        let digits = step < 0.1 ? 2 : step < 1 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    private func calendarCard(_ vehicle: Vehicle) -> some View {
        var calendar = Calendar.current
        calendar.firstWeekday = store.data.weekStartsMonday ? 2 : 1
        let interval = calendar.dateInterval(of: .month, for: displayedMonth)!
        let weekday = calendar.component(.weekday, from: interval.start)
        let firstWeekday = store.data.weekStartsMonday ? (weekday + 5) % 7 : weekday - 1
        let days = calendar.range(of: .day, in: .month, for: displayedMonth)!.count
        let trips = store.trips(for: vehicle.id).filter { $0.date >= interval.start && $0.date < interval.end }
        let weekdayLabels = store.data.weekStartsMonday ? ["月","火","水","木","金","土","日"] : ["日","月","火","水","木","金","土"]
        let selectedTrips = trips.filter { calendar.isDate($0.date, inSameDayAs: selectedCalendarDate) }
        return VStack(alignment: .leading, spacing: 12) {
            MonthNavigator(month: $displayedMonth)
            HStack { ForEach(weekdayLabels, id: \.self) { Text($0).font(.caption).foregroundStyle($0 == "日" ? .red : $0 == "土" ? theme.accent : CarLogStyle.label).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 6) {
                ForEach(0..<(firstWeekday + days), id: \.self) { index in
                    if index < firstWeekday { Color.clear.frame(height: 64) } else {
                        let day = index - firstWeekday + 1
                        let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start)!
                        let dayTrips = trips.filter { calendar.isDate($0.date, inSameDayAs: date) }
                        let total = dayTrips.reduce(0) { $0 + $1.distance }
                        let color = store.calendarColor(for: dayTrips)
                        let selected = calendar.isDate(date, inSameDayAs: selectedCalendarDate)
                        Button { selectedCalendarDate = date } label: {
                            VStack(spacing: 3) {
                                Text("\(day)").font(.subheadline)
                                    .frame(width: 28, height: 28)
                                    .background(calendar.isDateInToday(date) ? theme.accent : .clear, in: Circle())
                                    .foregroundStyle(calendar.isDateInToday(date) ? .white : .primary)
                                if !dayTrips.isEmpty {
                                    Text(total.formatted(.number.precision(.fractionLength(0...1))) + " km")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(color)
                                        .lineLimit(1).minimumScaleFactor(0.65)
                                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                                        .background(color.opacity(colorScheme == .dark ? 0.25 : 0.11), in: Capsule())
                                } else { Color.clear.frame(height: 18) }
                            }
                            .padding(.horizontal, 2).frame(maxWidth: .infinity).frame(height: 64)
                            .background(selected ? theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? theme.accent : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(.dateTime.month().day()) + "、" + total.formatted() + "キロメートル")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            Divider()
            Text(selectedCalendarDate, format: .dateTime.month().day().weekday(.wide)).font(.headline)
            HStack {
                Text("合計走行距離").foregroundStyle(.secondary)
                Spacer()
                Text(selectedTrips.reduce(0) { $0 + $1.distance }.formatted(.number.precision(.fractionLength(0...1))) + " km")
                    .font(.title2.bold()).monospacedDigit()
            }
            if selectedTrips.isEmpty {
                Text("この日の走行記録はありません。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(selectedTrips) { trip in
                Button { editingTrip = trip } label: {
                    HStack(spacing: 10) {
                        Circle().fill(store.driver(for: trip).color).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.driver(for: trip).name).font(.headline).foregroundStyle(.primary)
                            if trip.resolvedDriverID == DriverProfile.otherID,
                               let name = trip.customDriverName, !name.isEmpty {
                                Text(name).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(trip.date.formatted(.dateTime.hour().minute()) + "・" + trip.mode.displayName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(trip.distance.formatted(.number.precision(.fractionLength(0...1))) + " km")
                            .foregroundStyle(.primary).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 7).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.carLogCard(padding: 12)
    }

    private func distance(_ id: UUID, _ interval: DateInterval) -> String { store.totalDistance(vehicleID: id, interval: interval).formatted(.number.precision(.fractionLength(1))) + " Km" }
}

private extension View {
    func recordAction(filled: Bool, theme: CarLogTheme) -> some View {
        self.font(.headline).foregroundStyle(filled ? .white : theme.accent).frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(filled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.softAccent), in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
    }
}
