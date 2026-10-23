import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var recordType = 0
    @State private var period = 0
    @State private var month = Date().startOfMonth
    @State private var editingItem: RecordItem?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                if let vehicle = store.selectedVehicle {
                    VStack(spacing: 14) {
                        Text("履歴").screenTitleStyle()
                        VehicleSummaryRow(vehicle: vehicle).carLogCard(padding: 12)
                        Picker("記録の種類", selection: $recordType) {
                            Text("走行記録").tag(0)
                            Text("給油記録").tag(1)
                        }.pickerStyle(.segmented).labelsHidden()
                        Picker("表示期間", selection: $period) {
                            Text("月間").tag(0)
                            Text("年間").tag(1)
                        }.pickerStyle(.segmented).labelsHidden()
                        MonthNavigator(month: $month)
                        if recordType == 0 { tripHistory(vehicle) } else { fuelHistory(vehicle) }
                    }.padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingItem) { item in
            NavigationStack {
                switch item { case .trip(let value): TripEditorView(vehicleID: value.vehicleID, existing: value); case .fuel(let value): FuelEditorView(vehicleID: value.vehicleID, existing: value) }
            }
        }
    }

    @ViewBuilder private func tripHistory(_ vehicle: Vehicle) -> some View {
        let values = filteredTrips(vehicle.id)
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(period == 0 ? "月間走行距離" : "年間走行距離").foregroundStyle(CarLogStyle.label)
                Text(values.reduce(0) { $0 + $1.distance }.formatted(.number.precision(.fractionLength(1))) + " Km").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("記録 \(values.count)件").foregroundStyle(CarLogStyle.label)
            }.frame(maxWidth: .infinity, alignment: .leading).carLogCard()
            if values.isEmpty { EmptyStateView(symbol: "road.lanes", title: "走行記録がありません", message: "ホームから走行距離を登録できます。") }
            ForEach(values) { trip in
                Button { editingItem = .trip(trip) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trip.date, format: .dateTime.month().day().weekday(.abbreviated)).font(.headline).foregroundStyle(CarLogStyle.deepBlue)
                            if trip.mode == .odometer {
                                Text(trip.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(CarLogStyle.label)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(trip.distance.formatted(.number.precision(.fractionLength(1))) + " Km").font(.title3.bold()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                            Text(trip.mode.displayName).font(.subheadline).foregroundStyle(CarLogStyle.label).lineLimit(1).minimumScaleFactor(0.75)
                        }.frame(width: 132, alignment: .trailing)
                        Image(systemName: "chevron.right").foregroundStyle(CarLogStyle.label).frame(width: 10)
                    }.carLogCard(padding: 16)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func fuelHistory(_ vehicle: Vehicle) -> some View {
        let values = filteredFuels(vehicle.id)
        let liters = values.reduce(0) { $0 + $1.liters }
        let cost = values.reduce(0) { $0 + $1.totalPrice }
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                summaryCell(period == 0 ? "月間給油量" : "年間給油量", liters.formatted(.number.precision(.fractionLength(1))) + " L")
                Divider(); summaryCell(period == 0 ? "月間ガソリン代" : "年間ガソリン代", cost.formatted(.currency(code: "JPY").precision(.fractionLength(0))))
                Divider(); summaryCell(period == 0 ? "平均燃費" : "給油回数", period == 0 ? (store.averageFuelEfficiency(for: values).map { $0.formatted(.number.precision(.fractionLength(1))) + " Km/L" } ?? "計算待ち") : "\(values.count)回")
            }.carLogCard(padding: 14)
            if values.isEmpty { EmptyStateView(symbol: "fuelpump.fill", title: "給油記録がありません", message: "ホームから給油を登録できます。") }
            if period == 0 {
                ForEach(values) { fuel in
                    Button { editingItem = .fuel(fuel) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "fuelpump.fill").foregroundStyle(CarLogStyle.blue).frame(width: 42, height: 42).background(CarLogStyle.softBlue, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) { Text(fuel.date, format: .dateTime.month().day().weekday(.abbreviated)).font(.headline).foregroundStyle(CarLogStyle.deepBlue); Text(fuel.station.isEmpty ? "スタンド未設定" : fuel.station).font(.caption).foregroundStyle(CarLogStyle.label) }
                            Spacer()
                            VStack(alignment: .trailing) { Text(fuel.liters.formatted(.number.precision(.fractionLength(1))) + " L").font(.title3.bold()).foregroundStyle(.primary); Text(fuel.totalPrice.formatted(.currency(code: "JPY").precision(.fractionLength(0)))).foregroundStyle(CarLogStyle.label) }
                            Image(systemName: "chevron.right").foregroundStyle(CarLogStyle.label)
                        }.carLogCard(padding: 14)
                    }.buttonStyle(.plain)
                }
            } else {
                ForEach(fuelMonths(in: values), id: \.self) { fuelMonth in
                    let monthValues = values.filter { Calendar.current.isDate($0.date, equalTo: fuelMonth, toGranularity: .month) }
                    let monthLiters = monthValues.reduce(0) { $0 + $1.liters }
                    let monthCost = monthValues.reduce(0) { $0 + $1.totalPrice }
                    Button {
                        month = fuelMonth
                        withAnimation(.snappy) { period = 0 }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar").foregroundStyle(CarLogStyle.blue).frame(width: 42, height: 42).background(CarLogStyle.softBlue, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fuelMonth, format: .dateTime.month(.wide)).font(.headline).foregroundStyle(CarLogStyle.deepBlue)
                                Text("給油 \(monthValues.count)回").font(.caption).foregroundStyle(CarLogStyle.label)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(monthCost.formatted(.currency(code: "JPY").precision(.fractionLength(0)))).font(.title3.bold()).foregroundStyle(.primary)
                                Text(monthLiters.formatted(.number.precision(.fractionLength(1))) + " L").font(.subheadline).foregroundStyle(CarLogStyle.label)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(CarLogStyle.label)
                        }.carLogCard(padding: 14)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func fuelMonths(in values: [FuelRecord]) -> [Date] {
        let calendar = Calendar.current
        return Set(values.map { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date))! }).sorted(by: >)
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(CarLogStyle.label).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.headline).minimumScaleFactor(0.55).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
    private func filteredTrips(_ id: UUID) -> [TripRecord] { store.trips(for: id).filter { period == 0 ? month.monthInterval.contains($0.date) : Calendar.current.isDate($0.date, equalTo: month, toGranularity: .year) } }
    private func filteredFuels(_ id: UUID) -> [FuelRecord] { store.fuels(for: id).filter { period == 0 ? month.monthInterval.contains($0.date) : Calendar.current.isDate($0.date, equalTo: month, toGranularity: .year) } }
}

struct TripEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let vehicleID: UUID
    let existing: TripRecord?
    @State private var date: Date
    @State private var distance: Double
    @State private var odometer: Double
    @State private var mode: TripInputMode
    @State private var purpose: String
    @State private var note: String
    @State private var modeIndex: Int
    @State private var meterScan: MeterScanResult?
    @State private var pendingMeterScan: MeterScanResult?
    @State private var showsMeterSource = false
    @State private var showsMeterPicker = false
    @State private var meterImageSource: ImagePickerSource = .photoLibrary
    @State private var isRecognizingMeter = false
    @State private var meterError: String?
    @State private var showsMismatchConfirmation = false
    @State private var pendingDistanceRecord: TripRecord?
    @State private var distanceRecordToOverwrite: TripRecord?
    @State private var showsDistanceOverwriteConfirmation = false
    @State private var validationMessage: String?

    init(vehicleID: UUID, existing: TripRecord? = nil) {
        self.vehicleID = vehicleID; self.existing = existing
        _date = State(initialValue: existing?.date ?? Date()); _distance = State(initialValue: existing?.distance ?? 0); _odometer = State(initialValue: existing?.odometer ?? 0)
        _mode = State(initialValue: existing?.mode ?? .odometer); _purpose = State(initialValue: existing?.purpose ?? ""); _note = State(initialValue: existing?.note ?? "")
        _modeIndex = State(initialValue: existing == nil || existing?.mode == .odometer ? 1 : 0)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 14) {
                    if let vehicle = store.data.vehicles.first(where: { $0.id == vehicleID }) { VehicleSummaryRow(vehicle: vehicle, showsOdometer: true, showsChevron: false).carLogCard(padding: 12) }
                    Picker("入力方法", selection: $modeIndex) {
                        Text("走行距離").tag(0)
                        Text("ODOメーター").tag(1)
                    }.pickerStyle(.segmented).labelsHidden().onChange(of: modeIndex) { _, value in mode = value == 0 ? .distance : .odometer }
                    Button { showsMeterSource = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "camera").font(.title2).foregroundStyle(CarLogStyle.blue).frame(width: 48, height: 48).background(CarLogStyle.softBlue, in: Circle())
                            VStack(alignment: .leading) {
                                Text("メーターを撮影").font(.headline).foregroundStyle(CarLogStyle.blue)
                                Text(modeIndex == 0 ? "TRIP A・TRIP Bから走った距離を読み取ります" : "ODOから総走行距離を読み取ります").font(.subheadline).foregroundStyle(CarLogStyle.label)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(CarLogStyle.blue)
                        }.carLogCard(padding: 12)
                    }.buttonStyle(.plain)
                    DatePicker(modeIndex == 1 ? "日時" : "日付", selection: $date, displayedComponents: modeIndex == 1 ? [.date, .hourAndMinute] : .date).font(.headline).carLogCard()
                    LabeledNumberField(title: modeIndex == 0 ? "距離" : "オドメーター", unit: "Km", value: modeIndex == 0 ? $distance : $odometer).carLogCard()
                    TextField("目的（任意）", text: $purpose).carLogCard()
                    TextField("メモ（任意）", text: $note, axis: .vertical).carLogCard()
                    PrimaryActionButton(title: "記録を保存", action: save)
                    if let existing { Button("この記録を削除", role: .destructive) { store.deleteTrip(id: existing.id); dismiss() }.padding() }
                }.padding(18)
            }
        }
        .navigationTitle(existing == nil ? "走行距離を記録" : "走行記録を編集").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
        .sheet(isPresented: $showsMeterPicker) { ImagePicker(source: meterImageSource, onImage: recognizeMeter) }
        .sheet(item: $meterScan) { scan in
            NavigationStack {
                MeterOCRResultView(
                    scan: scan,
                    expectsOdometer: modeIndex == 1,
                    apply: { value in
                        if modeIndex == 1 { odometer = value; mode = .odometer }
                        else { distance = value; mode = .tripMeter }
                        meterScan = nil
                    },
                    retake: retakeTripMeter
                )
            }
        }
        .confirmationDialog("メーター画像を選択", isPresented: $showsMeterSource, titleVisibility: .visible) {
            Button("カメラで撮影") { meterImageSource = .camera; showsMeterPicker = true }
            Button("写真ライブラリから選択") { meterImageSource = .photoLibrary; showsMeterPicker = true }
            Button("キャンセル", role: .cancel) { }
        }
        .alert(mismatchTitle, isPresented: $showsMismatchConfirmation) {
            Button("撮り直す", role: .cancel) { pendingMeterScan = nil; showsMeterSource = true }
            Button("この画像を確認") { meterScan = pendingMeterScan; pendingMeterScan = nil }
        } message: { Text(mismatchMessage) }
        .alert("同日の走行距離記録があります", isPresented: $showsDistanceOverwriteConfirmation) {
            Button("キャンセル", role: .cancel) { pendingDistanceRecord = nil; distanceRecordToOverwrite = nil }
            Button("上書き", role: .destructive, action: overwriteDistanceRecord)
        } message: { Text("走行距離は1日1記録です。同日に保存されている記録を今回の内容で上書きしますか？") }
        .alert("読み取りできませんでした", isPresented: Binding(get: { meterError != nil }, set: { if !$0 { meterError = nil } })) { Button("OK", role: .cancel) { meterError = nil } } message: { Text(meterError ?? "メーターが正面からはっきり写るように撮影してください。") }
        .alert("入力内容を確認してください", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
            Button("OK", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
        .overlay { if isRecognizingMeter { ZStack { Color.black.opacity(0.18).ignoresSafeArea(); ProgressView("メーターを読み取っています…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } } }
    }

    private func save() {
        let startingOdometer = store.startingOdometer(vehicleID: vehicleID, editing: existing)
        let computedDistance = modeIndex == 0 ? distance : odometer - startingOdometer
        guard computedDistance > 0 else {
            validationMessage = modeIndex == 0
                ? "走行距離を0より大きい数値で入力してください。"
                : "オドメーターは走行開始時の値（\(startingOdometer.formatted(.number.precision(.fractionLength(0...1)))) Km）より大きい数値を入力してください。"
            return
        }
        let value = TripRecord(id: existing?.id ?? UUID(), vehicleID: vehicleID, date: date, distance: computedDistance, odometer: modeIndex == 1 ? odometer : nil, mode: mode, purpose: purpose, note: note)
        if modeIndex == 0,
           let duplicate = store.trips(for: vehicleID).first(where: { $0.mode != .odometer && $0.id != value.id && Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            pendingDistanceRecord = value
            distanceRecordToOverwrite = duplicate
            showsDistanceOverwriteConfirmation = true
            return
        }
        existing == nil ? store.addTrip(value) : store.updateTrip(value); dismiss()
    }

    private func overwriteDistanceRecord() {
        guard var pending = pendingDistanceRecord, let duplicate = distanceRecordToOverwrite else { return }
        if let existing, existing.id != duplicate.id { store.deleteTrip(id: existing.id) }
        pending.id = duplicate.id
        store.updateTrip(pending)
        pendingDistanceRecord = nil
        distanceRecordToOverwrite = nil
        dismiss()
    }

    private var mismatchTitle: String { modeIndex == 0 ? "ODO画面に見えます" : "TRIP画面に見えます" }
    private var mismatchMessage: String { modeIndex == 0 ? "トリップメーターの記録にはTRIP AまたはTRIP Bの表示が適しています。正しい画像か確認してください。" : "オドメーターの記録にはODOの表示が適しています。正しい画像か確認してください。" }
    private func retakeTripMeter() {
        meterScan = nil
        meterImageSource = .camera
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showsMeterPicker = true }
    }
    private func recognizeMeter(_ image: UIImage) {
        isRecognizingMeter = true
        Task {
            do {
                let scan = try await MeterOCRService.recognize(image)
                let mismatch = modeIndex == 0 ? (scan.tripValue == nil && scan.odometer != nil) : (scan.odometer == nil && scan.tripValue != nil)
                if mismatch { pendingMeterScan = scan; showsMismatchConfirmation = true }
                else { meterScan = scan }
            } catch { meterError = "画像からODOまたはTRIPの数値を認識できませんでした。" }
            isRecognizingMeter = false
        }
    }
}

struct MeterOCRResultView: View {
    let scan: MeterScanResult
    let expectsOdometer: Bool
    let apply: (Double) -> Void
    let retake: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double

    init(scan: MeterScanResult, expectsOdometer: Bool, apply: @escaping (Double) -> Void, retake: @escaping () -> Void) {
        self.scan = scan; self.expectsOdometer = expectsOdometer; self.apply = apply; self.retake = retake
        let recognized = expectsOdometer ? (scan.odometer ?? scan.tripValue ?? 0) : (scan.tripValue ?? scan.odometer ?? 0)
        _value = State(initialValue: recognized)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(uiImage: scan.image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 10)).carLogCard(padding: 8)
                    Text("認識した数値を確認してください").font(.headline).foregroundStyle(CarLogStyle.label)
                    if let odo = scan.odometer { readingRow(label: "ODO", reading: odo) }
                    if let tripA = scan.tripA { readingRow(label: "TRIP A", reading: tripA) }
                    if let tripB = scan.tripB { readingRow(label: "TRIP B", reading: tripB) }
                    LabeledNumberField(title: expectsOdometer ? "オドメーター" : "トリップメーター", unit: "Km", value: $value).carLogCard()
                    Text("数値をタップして修正できます").font(.subheadline).foregroundStyle(CarLogStyle.label)
                    PrimaryActionButton(title: "入力画面へ反映") { apply(value) }
                }.padding(18)
            }
        }
        .navigationTitle("読み取り結果").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("再撮影", action: retake) }
        }
    }

    private func readingRow(label: String, reading: Double) -> some View {
        let selected = abs(value - reading) < 0.0001
        return Button { value = reading } label: {
            HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? CarLogStyle.blue : CarLogStyle.label); Text(label).font(.headline); Spacer(); Text(reading.formatted(.number.precision(.fractionLength(0...1))) + " Km").font(.title3.bold()) }.foregroundStyle(.primary).carLogCard(padding: 14)
        }.buttonStyle(.plain)
    }
}

struct FuelEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let vehicleID: UUID
    let existing: FuelRecord?
    @State private var date: Date
    @State private var liters: Double
    @State private var totalPrice: Double
    @State private var odometer: Double
    @State private var isFull: Bool
    @State private var station: String
    @State private var note: String
    @State private var receiptScan: ReceiptScanResult?
    @State private var showsPhotoSource = false
    @State private var showsImagePicker = false
    @State private var imageSource: ImagePickerSource = .photoLibrary
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @State private var meterScan: MeterScanResult?
    @State private var pendingMeterScan: MeterScanResult?
    @State private var showsMeterSource = false
    @State private var showsMeterPicker = false
    @State private var meterImageSource: ImagePickerSource = .photoLibrary
    @State private var isRecognizingMeter = false
    @State private var meterError: String?
    @State private var showsMeterMismatch = false

    init(vehicleID: UUID, existing: FuelRecord? = nil) {
        self.vehicleID = vehicleID; self.existing = existing
        _date = State(initialValue: existing?.date ?? Date()); _liters = State(initialValue: existing?.liters ?? 0); _totalPrice = State(initialValue: existing?.totalPrice ?? 0)
        _odometer = State(initialValue: existing?.odometer ?? 0); _isFull = State(initialValue: existing?.isFull ?? true); _station = State(initialValue: existing?.station ?? ""); _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 14) {
                    if let vehicle = store.data.vehicles.first(where: { $0.id == vehicleID }) { VehicleSummaryRow(vehicle: vehicle, showsOdometer: true).carLogCard(padding: 12) }
                    Button { showsPhotoSource = true } label: { HStack(spacing: 16) { Image(systemName: "doc.viewfinder").font(.title2).foregroundStyle(CarLogStyle.blue); VStack(alignment: .leading) { Text("レシートを撮影").font(.headline).foregroundStyle(.primary); Text("日時・給油量・単価・店舗・金額を読み取ります").font(.subheadline).foregroundStyle(CarLogStyle.label) }; Spacer(); Image(systemName: "chevron.right") }.carLogCard() }.buttonStyle(.plain)
                    DatePicker("給油日時", selection: $date, displayedComponents: [.date, .hourAndMinute]).font(.headline).carLogCard()
                    HStack(spacing: 14) {
                        LabeledNumberField(title: "オドメーター", unit: "Km", value: $odometer)
                        Button { showsMeterSource = true } label: {
                            Image(systemName: "camera.fill").font(.title2).foregroundStyle(.white).frame(width: 54, height: 54).background(CarLogStyle.blue, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("オドメーターを撮影")
                    }.carLogCard()
                    HStack(spacing: 10) { LabeledNumberField(title: "給油量", unit: "L", value: $liters).carLogCard(); LabeledNumberField(title: "1Lあたり", unit: "円", value: unitPriceBinding).carLogCard() }
                    LabeledNumberField(title: "支払金額", unit: "円", value: $totalPrice).carLogCard()
                    TextField("ガソリンスタンド", text: $station).carLogCard()
                    Toggle(isOn: $isFull) { VStack(alignment: .leading) { Text("満タン給油").font(.headline); Text("部分給油の場合はオフ").font(.subheadline).foregroundStyle(CarLogStyle.label) } }.tint(CarLogStyle.blue).carLogCard()
                    PrimaryActionButton(title: "給油記録を保存", action: save)
                    if let existing { Button("この記録を削除", role: .destructive) { store.deleteFuel(id: existing.id); dismiss() }.padding() }
                }.padding(18)
            }
        }
        .navigationTitle(existing == nil ? "給油を記録" : "給油記録を編集").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
        .sheet(isPresented: $showsImagePicker) { ImagePicker(source: imageSource, onImage: recognizeReceipt) }
        .sheet(isPresented: $showsMeterPicker) { ImagePicker(source: meterImageSource, onImage: recognizeFuelMeter) }
        .sheet(item: $receiptScan) { scan in
            NavigationStack {
                ReceiptOCRResultView(
                    scan: scan,
                    apply: { result in
                        date = result.date; liters = result.liters; totalPrice = result.totalPrice; station = result.station
                        receiptScan = nil
                    },
                    retake: retakeReceipt
                )
            }
        }
        .sheet(item: $meterScan) { scan in
            NavigationStack {
                MeterOCRResultView(
                    scan: scan,
                    expectsOdometer: true,
                    apply: { value in odometer = value; meterScan = nil },
                    retake: retakeFuelMeter
                )
            }
        }
        .confirmationDialog("レシート画像を選択", isPresented: $showsPhotoSource, titleVisibility: .visible) {
            Button("カメラで撮影") { imageSource = .camera; showsImagePicker = true }
            Button("写真ライブラリから選択") { imageSource = .photoLibrary; showsImagePicker = true }
            Button("キャンセル", role: .cancel) { }
        }
        .confirmationDialog("オドメーター画像を選択", isPresented: $showsMeterSource, titleVisibility: .visible) {
            Button("カメラで撮影") { meterImageSource = .camera; showsMeterPicker = true }
            Button("写真ライブラリから選択") { meterImageSource = .photoLibrary; showsMeterPicker = true }
            Button("キャンセル", role: .cancel) { }
        }
        .alert("TRIP画面に見えます", isPresented: $showsMeterMismatch) {
            Button("撮り直す", role: .cancel) { pendingMeterScan = nil; showsMeterSource = true }
            Button("この画像を確認") { meterScan = pendingMeterScan; pendingMeterScan = nil }
        } message: { Text("給油記録のオドメーターにはODOの表示が適しています。TRIP AまたはTRIP Bの画像ではないか確認してください。") }
        .overlay { if isRecognizing || isRecognizingMeter { ZStack { Color.black.opacity(0.18).ignoresSafeArea(); ProgressView(isRecognizingMeter ? "メーターを読み取っています…" : "レシートを読み取っています…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } } }
        .alert("読み取りできませんでした", isPresented: Binding(get: { recognitionError != nil }, set: { if !$0 { recognitionError = nil } })) { Button("OK", role: .cancel) { recognitionError = nil } } message: { Text(recognitionError ?? "別の画像を選択するか、手入力してください。") }
        .alert("メーターを読み取れませんでした", isPresented: Binding(get: { meterError != nil }, set: { if !$0 { meterError = nil } })) { Button("OK", role: .cancel) { meterError = nil } } message: { Text(meterError ?? "ODOがはっきり写るように撮影してください。") }
    }

    private var unitPriceBinding: Binding<Double> { Binding(get: { liters > 0 ? totalPrice / liters : 0 }, set: { totalPrice = $0 * liters }) }
    private func save() { guard liters > 0, totalPrice > 0 else { return }; let value = FuelRecord(id: existing?.id ?? UUID(), vehicleID: vehicleID, date: date, liters: liters, totalPrice: totalPrice, odometer: odometer, isFull: isFull, station: station, note: note); existing == nil ? store.addFuel(value) : store.updateFuel(value); dismiss() }
    private func retakeReceipt() {
        receiptScan = nil
        imageSource = .camera
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showsImagePicker = true }
    }
    private func retakeFuelMeter() {
        meterScan = nil
        meterImageSource = .camera
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showsMeterPicker = true }
    }
    private func recognizeReceipt(_ image: UIImage) {
        isRecognizing = true
        Task {
            do { receiptScan = try await ReceiptOCRService.recognize(image) }
            catch { recognitionError = "画像から文字を認識できませんでした。" }
            isRecognizing = false
        }
    }
    private func recognizeFuelMeter(_ image: UIImage) {
        isRecognizingMeter = true
        Task {
            do {
                let scan = try await MeterOCRService.recognize(image)
                if scan.odometer == nil && scan.tripValue != nil { pendingMeterScan = scan; showsMeterMismatch = true }
                else { meterScan = scan }
            } catch { meterError = "画像からODOの数値を認識できませんでした。" }
            isRecognizingMeter = false
        }
    }
}

struct ReceiptOCRResultView: View {
    let original: ReceiptScanResult
    let apply: (ReceiptScanResult) -> Void
    let retake: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var liters: Double
    @State private var unitPrice: Double
    @State private var totalPrice: Double
    @State private var station: String

    init(scan: ReceiptScanResult, apply: @escaping (ReceiptScanResult) -> Void, retake: @escaping () -> Void) {
        original = scan; self.apply = apply; self.retake = retake
        _date = State(initialValue: scan.date); _liters = State(initialValue: scan.liters); _unitPrice = State(initialValue: scan.unitPrice)
        _totalPrice = State(initialValue: scan.totalPrice); _station = State(initialValue: scan.station)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(uiImage: original.image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 10)).carLogCard(padding: 8)
                    Text("認識した内容を確認してください").font(.headline).foregroundStyle(CarLogStyle.label)
                    DatePicker("給油日時", selection: $date, displayedComponents: [.date, .hourAndMinute]).carLogCard()
                    LabeledNumberField(title: "給油量", unit: "L", value: $liters).carLogCard()
                    LabeledNumberField(title: "1Lあたり", unit: "円", value: $unitPrice).carLogCard()
                    LabeledNumberField(title: "支払金額", unit: "円", value: $totalPrice).carLogCard()
                    TextField("ガソリンスタンド（未設定）", text: $station).carLogCard()
                    PrimaryActionButton(title: "給油画面へ反映") {
                        let finalTotal = totalPrice > 0 ? totalPrice : liters * unitPrice
                        apply(ReceiptScanResult(image: original.image, date: date, liters: liters, unitPrice: unitPrice, totalPrice: finalTotal, station: station, recognizedText: original.recognizedText))
                    }
                }.padding(18)
            }
        }
        .navigationTitle("レシート読み取り").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("再撮影", action: retake) }
        }
    }
}
