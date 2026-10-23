import Charts
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.carLogTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var metric: Int
    @State private var period = 0
    @State private var selectedMonth = Date()
    @State private var selectedChartDate: Date?

    init(metric: Binding<Int> = .constant(0)) {
        _metric = metric
    }

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        var secondary: Double? = nil
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                if let vehicle = store.selectedVehicle {
                    VStack(spacing: 14) {
                        Text("分析").screenTitleStyle()
                        VehicleSummaryRow(vehicle: vehicle).carLogCard(padding: 12)
                        Picker("分析項目", selection: $metric) {
                            Text("走行距離").tag(0)
                            Text("燃費").tag(1)
                            Text("ガソリン代").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: metric) { _, _ in period = 0; selectedChartDate = nil }
                        Picker("表示期間", selection: $period) {
                            ForEach(periodLabels.indices, id: \.self) { index in
                                Text(periodLabels[index]).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        periodNavigator.padding(.vertical, 5)
                        if hasSufficientData(vehicle.id) {
                            summaryCard(vehicle)
                            chartCard(vehicle)
                            insightCard(vehicle)
                        } else {
                            insufficientDataCard(vehicle.id)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, analysisCalendar)
        .onChange(of: period) { _, _ in selectedChartDate = nil }
        .onChange(of: selectedMonth) { _, _ in selectedChartDate = nil }
        .onChange(of: store.selectedVehicle?.id) { _, _ in selectedChartDate = nil }
    }

    private var periodLabels: [String] { metric == 0 ? ["週間", "月間", "年間"] : ["月間", "年間"] }

    private var periodNavigator: some View {
        HStack {
            Button { movePeriod(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline).foregroundStyle(theme.deepAccent)
                    .frame(width: 42, height: 42).background(theme.softAccent, in: Circle())
            }
            Spacer()
            Text(periodTitle).font(.title2.bold()).multilineTextAlignment(.center)
            Spacer()
            Button { movePeriod(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline).foregroundStyle(theme.deepAccent)
                    .frame(width: 42, height: 42).background(theme.softAccent, in: Circle())
            }
        }
    }

    private var periodTitle: String {
        if metric == 0 && period == 0 {
            let endDate = analysisCalendar.date(byAdding: .day, value: -1, to: selectedInterval.end)!
            let start = selectedInterval.start.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP")))
            let end = endDate.formatted(.dateTime.month().day().locale(Locale(identifier: "ja_JP")))
            return "\(start)〜\(end)"
        }
        if isYearlyPeriod {
            return selectedMonth.formatted(.dateTime.year().locale(Locale(identifier: "ja_JP")))
        }
        return selectedMonth.formatted(.dateTime.year().month().locale(Locale(identifier: "ja_JP")))
    }

    private func movePeriod(by value: Int) {
        let component: Calendar.Component
        if metric == 0 && period == 0 {
            component = .weekOfYear
        } else if isYearlyPeriod {
            component = .year
        } else {
            component = .month
        }
        if let moved = analysisCalendar.date(byAdding: component, value: value, to: selectedMonth) {
            selectedMonth = moved
        }
    }

    @ViewBuilder private func summaryCard(_ vehicle: Vehicle) -> some View {
        let trips = filteredTrips(vehicle.id)
        let fuels = filteredFuels(vehicle.id)
        let distance = trips.reduce(0) { $0 + $1.distance }
        let efficiencies = fuels.compactMap(store.fuelEfficiency)
        let averageEfficiency = efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)
        let fuelCost = fuels.reduce(0) { $0 + $1.totalPrice }
        let averageUnitPrice = fuels.isEmpty ? nil : fuels.map(\.unitPrice).reduce(0, +) / Double(fuels.count)
        HStack(spacing: 0) {
            if metric == 0 {
                summaryCell("走行距離", distance.formatted(.number.precision(.fractionLength(1))) + " Km")
                divider
                summaryCell("1日平均", (distance / Double(max(1, dayCount))).formatted(.number.precision(.fractionLength(1))) + " Km")
                divider
                summaryCell("前期比", hasPreviousData(vehicle.id) ? comparisonText(current: distance, previous: previousDistance(vehicle.id)) : previousDataRequirement, accent: theme.accent)
            } else if metric == 1 {
                summaryCell("平均燃費", efficiencyText(averageEfficiency)); divider
                summaryCell("最高燃費", efficiencyText(efficiencies.max())); divider
                summaryCell("前期比", hasPreviousData(vehicle.id) ? deltaEfficiency(current: averageEfficiency, previous: previousEfficiency(vehicle.id)) : previousDataRequirement, accent: theme.accent)
            } else {
                summaryCell("ガソリン代", yen(fuelCost)); divider
                summaryCell("平均単価", averageUnitPrice.map { yen($0) + "/L" } ?? "データ不足"); divider
                summaryCell("前期比", hasPreviousData(vehicle.id) ? costDifference(current: fuelCost, previous: previousFuelCost(vehicle.id)) : previousDataRequirement, accent: .mint)
            }
        }.carLogCard(padding: 12)
    }

    private var divider: some View { Rectangle().fill(CarLogStyle.border).frame(width: 1, height: 66) }
    private func summaryCell(_ title: String, _ value: String, accent: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(CarLogStyle.label)
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.55)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }

    @ViewBuilder private func chartCard(_ vehicle: Vehicle) -> some View {
        let points = chartPoints(vehicle.id)
        VStack(alignment: .leading, spacing: 16) {
            Text(chartTitle).font(.title3.bold()).foregroundStyle(CarLogStyle.deepBlue)
            if points.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(theme.accent.opacity(0.55))
                    Text("この期間のデータはありません").font(.subheadline).foregroundStyle(CarLogStyle.label)
                }.frame(maxWidth: .infinity).frame(height: 220)
            } else if metric == 0 {
                Chart(points) { point in
                    BarMark(x: .value("日付", point.date, unit: period == 2 ? .month : .day), y: .value("距離", point.value))
                        .foregroundStyle(barColor(for: point, points: points, color: theme.accent).gradient).cornerRadius(3)
                }
                .chartXAxis { dateAxisMarks }
                .chartYAxis { numberAxisMarks }
                .chartXScale(domain: selectedInterval.start...selectedInterval.end)
                .chartOverlay { proxy in selectionOverlay(proxy, points: points) }
                .chartYAxisLabel("走行距離（Km）").frame(height: 280)
            } else if metric == 1 {
                Chart(points) { point in
                    AreaMark(x: .value("日付", plottedDate(point.date)), y: .value("燃費", point.value))
                        .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("日付", plottedDate(point.date)), y: .value("燃費", point.value)).foregroundStyle(theme.accent).lineStyle(.init(lineWidth: 3)).interpolationMethod(.catmullRom)
                    PointMark(x: .value("日付", plottedDate(point.date)), y: .value("燃費", point.value)).foregroundStyle(theme.accent).symbolSize(55)
                }
                .chartXAxis { dateAxisMarks }
                .chartYAxis { numberAxisMarks }
                .chartXScale(domain: selectedInterval.start...selectedInterval.end)
                .chartOverlay { proxy in selectionOverlay(proxy, points: points) }
                .chartYAxisLabel("燃費（Km/L）").frame(height: 280)
            } else {
                Chart(points) { point in
                    BarMark(x: .value("日付", point.date, unit: isYearlyPeriod ? .month : .day), y: .value("支払額", point.value)).foregroundStyle(barColor(for: point, points: points, color: fuelCostBarColor).gradient).cornerRadius(3)
                    if let secondary = point.secondary {
                        LineMark(x: .value("日付", plottedDate(point.date)), y: .value("単価", secondary * 30)).foregroundStyle(fuelUnitPriceColor).lineStyle(.init(lineWidth: 3)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("日付", plottedDate(point.date)), y: .value("単価", secondary * 30)).foregroundStyle(fuelUnitPriceColor).symbolSize(65)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.number.precision(.fractionLength(0)))).font(.caption2.monospacedDigit())
                            }
                        }
                    }
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let scaledPrice = value.as(Double.self) {
                                Text((scaledPrice / 30).formatted(.number.precision(.fractionLength(0)))).font(.caption2.monospacedDigit())
                                    .foregroundStyle(fuelUnitPriceColor)
                            }
                        }
                    }
                }
                .chartXAxis { dateAxisMarks }
                .chartXScale(domain: selectedInterval.start...selectedInterval.end)
                .chartOverlay { proxy in selectionOverlay(proxy, points: points) }
                .frame(height: 280)
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("棒：支払額", systemImage: "rectangle.fill").foregroundStyle(fuelCostBarColor)
                        Text("左の目盛り・円").foregroundStyle(CarLogStyle.label)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Label("折れ線：1Lあたり", systemImage: "circle").foregroundStyle(fuelUnitPriceColor)
                        Text("右の目盛り・円/L").foregroundStyle(fuelUnitPriceColor)
                    }
                }.font(.caption)
            }
            if !points.isEmpty {
                Label("グラフをタップして日付・数値を表示", systemImage: "hand.tap")
                    .font(.caption).foregroundStyle(CarLogStyle.label)
            }
        }.carLogCard(padding: 16)
    }

    private func insightCard(_ vehicle: Vehicle) -> some View {
        HStack(spacing: 16) {
            Image(systemName: insightImproved(vehicle.id) ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis").font(.title2.bold()).foregroundStyle(theme.accent).frame(width: 48, height: 48).background(theme.softAccent, in: Circle())
            Text(insightText(vehicle.id)).font(.headline).foregroundStyle(CarLogStyle.deepBlue); Spacer()
        }.carLogCard(padding: 14)
    }

    private func insufficientDataCard(_ vehicleID: UUID) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 38)).foregroundStyle(theme.accent.opacity(0.65))
            Text("分析に必要なデータが足りません").font(.title3.bold())
            Text(requiredDataDescription).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(CarLogStyle.label)
            Text(currentDataDescription(vehicleID))
                .font(.subheadline.bold()).foregroundStyle(theme.deepAccent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.softAccent, in: Capsule())
        }.frame(maxWidth: .infinity).padding(.vertical, 42).carLogCard(padding: 18)
    }

    private var requiredDataDescription: String {
        switch metric {
        case 0:
            return "選択中の\(selectedPeriodLabel)に走行距離を1件登録すると、グラフと集計を表示できます。"
        case 1:
            return "燃費は、前回と今回の満タン給油で記録したオドメーターの差から計算します。満タン給油を2回以上記録してください。"
        default:
            return "選択中の\(selectedPeriodLabel)に給油記録を1件登録すると、グラフと集計を表示できます。"
        }
    }

    private func currentDataDescription(_ vehicleID: UUID) -> String {
        switch metric {
        case 0:
            let count = filteredTrips(vehicleID).count
            return count == 0 ? "現在0件・あと1件必要です" : "現在\(count)件・表示できます"
        case 1:
            let fullTankCount = store.fuels(for: vehicleID).filter { $0.isFull && $0.date < selectedInterval.end }.count
            let calculableCount = filteredFuels(vehicleID).compactMap(store.fuelEfficiency).count
            if calculableCount > 0 { return "計算できる燃費が\(calculableCount)件あります" }
            if fullTankCount < 2 { return "満タン給油は現在\(fullTankCount)回・あと\(2 - fullTankCount)回必要です" }
            return "オドメーターが前回より増えているか確認してください"
        default:
            let count = filteredFuels(vehicleID).count
            return count == 0 ? "現在0件・あと1件必要です" : "現在\(count)件・表示できます"
        }
    }

    private func plottedDate(_ date: Date) -> Date {
        let interval = analysisCalendar.dateInterval(of: isYearlyPeriod ? .month : .day, for: date)!
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    private var axisDates: [Date] {
        let calendar = analysisCalendar
        let start = selectedInterval.start
        if isYearlyPeriod {
            let step = dynamicTypeSize.isAccessibilitySize ? 3 : 2
            return stride(from: 0, to: 12, by: step).compactMap {
                calendar.date(byAdding: .month, value: $0, to: start).map(plottedDate)
            }
        }
        if metric == 0 && period == 0 {
            let offsets = dynamicTypeSize.isAccessibilitySize ? [0, 3, 6] : Array(0..<7)
            return offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: start).map(plottedDate) }
        }
        let last = calendar.range(of: .day, in: .month, for: start)!.count
        var days = dynamicTypeSize.isAccessibilitySize ? [1, 10, 20] : [1, 5, 10, 15, 20, 25]
        days.removeAll { last - $0 < 4 }
        days.append(last)
        return days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start).map(plottedDate) }
    }

    @AxisContentBuilder private var dateAxisMarks: some AxisContent {
        AxisMarks(position: .bottom, values: axisDates) { value in
            AxisTick()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    if isYearlyPeriod {
                        Text("\(analysisCalendar.component(.month, from: date))月")
                            .font(.caption2.monospacedDigit()).lineLimit(1)
                    } else if metric == 0 && period == 0 {
                        VStack(spacing: 2) {
                            Text("\(analysisCalendar.component(.month, from: date))/\(analysisCalendar.component(.day, from: date))")
                            Text(date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(CarLogStyle.label)
                        }.font(.caption2.monospacedDigit()).fixedSize()
                    } else {
                        Text("\(analysisCalendar.component(.day, from: date))日")
                            .font(.caption2.monospacedDigit()).lineLimit(1)
                    }
                }
            }
        }
    }

    @AxisContentBuilder private var numberAxisMarks: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(CarLogStyle.border.opacity(0.5))
            AxisTick()
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(number.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }

    private func selectedPoint(in points: [Point]) -> Point? {
        guard let selectedChartDate else { return nil }
        return points.min { abs(plottedDate($0.date).timeIntervalSince(selectedChartDate))
            < abs(plottedDate($1.date).timeIntervalSince(selectedChartDate)) }
    }

    private func barColor(for point: Point, points: [Point], color: Color) -> Color {
        guard let selected = selectedPoint(in: points) else { return color }
        return point.id == selected.id ? color : color.opacity(0.35)
    }

    private func selectionOverlay(_ proxy: ChartProxy, points: [Point]) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { event in
                        guard plot.contains(event.location) else { return }
                        selectedChartDate = proxy.value(atX: event.location.x - plot.minX, as: Date.self)
                    })
                if let point = selectedPoint(in: points),
                   let plotX = proxy.position(forX: plottedDate(point.date)),
                   let plotY = proxy.position(forY: point.value) {
                    let x = plot.minX + plotX
                    let y = plot.minY + plotY
                    let width = min(180, geometry.size.width)
                    let halfHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 70 : 38
                    Path { path in
                        path.move(to: CGPoint(x: x, y: plot.minY))
                        path.addLine(to: CGPoint(x: x, y: plot.maxY))
                    }.stroke(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .allowsHitTesting(false)
                    Circle().fill(theme.accent).frame(width: 8, height: 8)
                        .position(x: x, y: y).allowsHitTesting(false)
                    selectionDetail(point)
                        .frame(width: width)
                        .position(x: min(max(x, width / 2), geometry.size.width - width / 2),
                                  y: max(halfHeight, y - halfHeight - 10))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func selectionDetail(_ point: Point) -> some View {
        VStack(spacing: 4) {
            if isYearlyPeriod {
                Text(point.date, format: .dateTime.year().month()).font(.caption)
            } else {
                Text(point.date, format: .dateTime.month().day().weekday(.abbreviated)).font(.caption)
            }
            Text(metric == 0 ? point.value.formatted(.number.precision(.fractionLength(0...1))) + " Km"
                 : metric == 1 ? point.value.formatted(.number.precision(.fractionLength(1))) + " Km/L" : yen(point.value))
                .font(.subheadline.bold().monospacedDigit())
            if metric == 2, let unitPrice = point.secondary {
                Text("単価 \(yen(unitPrice))/L").font(.caption).foregroundStyle(fuelUnitPriceColor)
            }
        }
        .foregroundStyle(.primary).padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CarLogStyle.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
    }

    private var isYearlyPeriod: Bool { (metric == 0 && period == 2) || (metric != 0 && period == 1) }

    private var selectedPeriodLabel: String { periodLabels.indices.contains(period) ? periodLabels[period] : periodLabels[0] }
    private var previousDataRequirement: String { metric == 1 ? "前期燃費1件必要" : "前期記録1件必要" }

    private var chartTitle: String { switch metric { case 0: isYearlyPeriod ? "月別の走行距離" : "日別の走行距離"; case 1: "燃費の推移"; default: "支払額と単価の推移" } }
    private var fuelCostBarColor: Color {
        colorScheme == .dark ? Color(hex: "55AFFF") : Color(hex: "126FC5")
    }
    private var fuelUnitPriceColor: Color {
        colorScheme == .dark ? Color(hex: "FFB84D") : Color(hex: "C75B00")
    }
    private var analysisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .current
        calendar.firstWeekday = store.data.weekStartsMonday ? 2 : 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }
    private var selectedInterval: DateInterval {
        let calendar = analysisCalendar
        if metric == 0 && period == 0 { return calendar.dateInterval(of: .weekOfYear, for: selectedMonth)! }
        let yearly = (metric == 0 && period == 2) || (metric != 0 && period == 1)
        return calendar.dateInterval(of: yearly ? .year : .month, for: selectedMonth)!
    }
    private var previousInterval: DateInterval {
        let calendar = analysisCalendar
        let component: Calendar.Component = ((metric == 0 && period == 2) || (metric != 0 && period == 1)) ? .year : ((metric == 0 && period == 0) ? .weekOfYear : .month)
        let date = calendar.date(byAdding: component, value: -1, to: selectedInterval.start)!
        return calendar.dateInterval(of: component, for: date)!
    }
    private var dayCount: Int { analysisCalendar.dateComponents([.day], from: selectedInterval.start, to: selectedInterval.end).day ?? 1 }
    private func filteredTrips(_ id: UUID) -> [TripRecord] { store.trips(for: id).filter { $0.date >= selectedInterval.start && $0.date < selectedInterval.end } }
    private func filteredFuels(_ id: UUID) -> [FuelRecord] { store.fuels(for: id).filter { $0.date >= selectedInterval.start && $0.date < selectedInterval.end }.sorted { $0.date < $1.date } }
    private func previousDistance(_ id: UUID) -> Double { store.trips(for: id).filter { previousInterval.contains($0.date) }.reduce(0) { $0 + $1.distance } }
    private func previousFuelCost(_ id: UUID) -> Double { store.fuels(for: id).filter { previousInterval.contains($0.date) }.reduce(0) { $0 + $1.totalPrice } }
    private func previousEfficiency(_ id: UUID) -> Double? { let values = store.fuels(for: id).filter { previousInterval.contains($0.date) }.compactMap(store.fuelEfficiency); return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    private func hasSufficientData(_ id: UUID) -> Bool {
        switch metric { case 0: !filteredTrips(id).isEmpty; case 1: !filteredFuels(id).compactMap(store.fuelEfficiency).isEmpty; default: !filteredFuels(id).isEmpty }
    }
    private func hasPreviousData(_ id: UUID) -> Bool {
        switch metric {
        case 0: return store.trips(for: id).contains { previousInterval.contains($0.date) }
        case 1: return previousEfficiency(id) != nil
        default: return store.fuels(for: id).contains { previousInterval.contains($0.date) }
        }
    }
    private func chartPoints(_ id: UUID) -> [Point] {
        if metric == 0 {
            let component: Calendar.Component = period == 2 ? .month : .day
            let grouped = Dictionary(grouping: filteredTrips(id)) { analysisCalendar.dateInterval(of: component, for: $0.date)!.start }
            return grouped.map { Point(date: $0.key, value: $0.value.reduce(0) { $0 + $1.distance }) }.sorted { $0.date < $1.date }
        }
        let component: Calendar.Component = isYearlyPeriod ? .month : .day
        let groupedFuels = Dictionary(grouping: filteredFuels(id)) { analysisCalendar.dateInterval(of: component, for: $0.date)!.start }
        if metric == 1 {
            return groupedFuels.compactMap { date, fuels in
                let values = fuels.compactMap(store.fuelEfficiency)
                guard !values.isEmpty else { return nil }
                return Point(date: date, value: values.reduce(0, +) / Double(values.count))
            }.sorted { $0.date < $1.date }
        }
        return groupedFuels.map { date, fuels in
            let liters = fuels.reduce(0) { $0 + $1.liters }
            let cost = fuels.reduce(0) { $0 + $1.totalPrice }
            return Point(date: date, value: cost, secondary: liters > 0 ? cost / liters : nil)
        }.sorted { $0.date < $1.date }
    }
    private func yen(_ value: Double) -> String { "¥" + value.formatted(.number.precision(.fractionLength(0))) }
    private func efficiencyText(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(1))) + " Km/L" } ?? "データ不足" }
    private func comparisonText(current: Double, previous: Double) -> String { previous > 0 ? String(format: "%+.1f%%", (current / previous - 1) * 100) : "—" }
    private func deltaEfficiency(current: Double?, previous: Double?) -> String { guard let current, let previous else { return "データ不足" }; return String(format: "%+.1f Km/L", current - previous) }
    private func costDifference(current: Double, previous: Double) -> String { previous > 0 ? String(format: "%@%@", current - previous >= 0 ? "+" : "-", yen(abs(current - previous))) : "—" }
    private func insightImproved(_ id: UUID) -> Bool { metric == 2 ? previousFuelCost(id) >= filteredFuels(id).reduce(0) { $0 + $1.totalPrice } : true }
    private func insightText(_ id: UUID) -> String {
        guard hasPreviousData(id) else { return "前期間のデータが不足しているため、比較は表示しません" }
        switch metric {
        case 0:
            let diff = filteredTrips(id).reduce(0) { $0 + $1.distance } - previousDistance(id)
            return diff >= 0 ? "前期より \(diff.formatted(.number.precision(.fractionLength(1)))) Km多く走っています" : "前期より \(abs(diff).formatted(.number.precision(.fractionLength(1)))) Km少ない走行です"
        case 1:
            let current = filteredFuels(id).compactMap(store.fuelEfficiency).reduce(0, +) / Double(filteredFuels(id).compactMap(store.fuelEfficiency).count)
            let previous = previousEfficiency(id) ?? current
            let diff = current - previous
            return diff >= 0 ? "前期より \(abs(diff).formatted(.number.precision(.fractionLength(1)))) Km/L燃費が良くなっています" : "前期より \(abs(diff).formatted(.number.precision(.fractionLength(1)))) Km/L燃費が低下しています"
        default:
            let diff = filteredFuels(id).reduce(0) { $0 + $1.totalPrice } - previousFuelCost(id)
            return diff <= 0 ? "前期より \(yen(abs(diff)))少なくなっています" : "前期より \(yen(diff))増えています"
        }
    }
}
