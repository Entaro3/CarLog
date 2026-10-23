import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.carLogTheme) private var theme
    @State private var editingVehicle: Vehicle?
    @State private var addingVehicle = false
    @State private var backupExport: BackupExport?
    @State private var exportError: String?
    @State private var showsAbout = false
    @State private var showsRestoreConfirmation = false
    @State private var showsRestoreImporter = false
    @State private var restoreMessage: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("車両") {
                        VStack(spacing: 0) {
                            ForEach(store.data.vehicles) { vehicle in
                                Button { editingVehicle = vehicle } label: {
                                    HStack(spacing: 14) {
                                        VehicleThumbnail(vehicle: vehicle, size: 62)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(vehicle.nickname.isEmpty ? vehicle.name : vehicle.nickname).font(.title3.bold()).foregroundStyle(.primary)
                                            HStack(spacing: 10) {
                                                if vehicle.isPrimary { Text("メイン車両").font(.caption.bold()).foregroundStyle(CarLogStyle.blue).padding(.horizontal, 8).padding(.vertical, 4).background(CarLogStyle.softBlue, in: RoundedRectangle(cornerRadius: 6)) }
                                                Circle().fill(Color(hex: vehicle.primaryColorHex)).frame(width: 16, height: 16)
                                                Text(vehicle.mood.rawValue).font(.subheadline).foregroundStyle(CarLogStyle.label)
                                            }
                                        }
                                        Spacer(); chevron
                                    }.padding(14)
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 14)
                            }
                            Button { addingVehicle = true } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(CarLogStyle.blue, in: Circle())
                                    Text("車両を追加").font(.headline).foregroundStyle(CarLogStyle.blue)
                                    Spacer(); chevron
                                }.padding(14)
                            }.buttonStyle(.plain)
                        }.settingsCard()
                    }

                    section("ユーザー") {
                        NavigationLink { DriverManagementView() } label: {
                            rowLabel(symbol: "person.2.fill", title: "ユーザー管理", value: nil)
                        }.buttonStyle(.plain).settingsCard()
                    }

                    section("表示") {
                        VStack(spacing: 0) {
                            Menu {
                                Button { store.setWeekStartsMonday(true) } label: { if store.data.weekStartsMonday { Label("月曜日", systemImage: "checkmark") } else { Text("月曜日") } }
                                Button { store.setWeekStartsMonday(false) } label: { if !store.data.weekStartsMonday { Label("日曜日", systemImage: "checkmark") } else { Text("日曜日") } }
                            } label: { rowLabel(symbol: "calendar", title: "週の開始曜日", value: store.data.weekStartsMonday ? "月曜日" : "日曜日") }
                            Divider().padding(.leading, 62)
                            Menu {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Button { store.setAppearanceMode(appearance) } label: { if store.appearanceMode == appearance { Label(appearance.rawValue, systemImage: "checkmark") } else { Text(appearance.rawValue) } }
                                }
                            } label: { rowLabel(symbol: "paintpalette", title: "外観モード", value: store.appearanceMode.rawValue) }
                        }.settingsCard()
                    }

                    section("データ") {
                        VStack(spacing: 0) {
                            Button {
                                do { backupExport = BackupExport(url: try store.exportURL()) }
                                catch { exportError = "バックアップを書き出せませんでした。空き容量や車両写真を確認してください。" }
                            } label: {
                                rowLabel(symbol: "square.and.arrow.up", title: "データを書き出す", value: "写真付きバックアップ")
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 62)
                            row(symbol: "arrow.counterclockwise", title: "バックアップを復元", value: nil) { showsRestoreConfirmation = true }
                        }.settingsCard()
                    }

                    section("アプリ") {
                        VStack(spacing: 0) {
                            row(symbol: "info.circle", title: "カーログについて", value: nil) { showsAbout = true }
                            Divider().padding(.leading, 62)
                            rowLabel(symbol: "doc.text", title: "バージョン", value: "1.0", showsChevron: false)
                        }.settingsCard()
                    }
                }.padding(.horizontal, 18).padding(.vertical, 12).padding(.bottom, 28)
            }
        }
        .navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingVehicle) { NavigationStack { VehicleEditorView() } }
        .sheet(item: $editingVehicle) { vehicle in NavigationStack { VehicleEditorView(existing: vehicle) } }
        .sheet(item: $backupExport) { backup in BackupShareSheet(url: backup.url) }
        .alert("書き出しエラー", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .alert("カーログについて", isPresented: $showsAbout) { Button("OK", role: .cancel) { } } message: { Text("現在準備中です。") }
        .alert("バックアップを復元", isPresented: $showsRestoreConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("ファイルを選択", role: .destructive) { showsRestoreImporter = true }
        } message: { Text("現在の車両・走行・給油データは、選択したバックアップの内容に置き換わります。") }
        .fileImporter(isPresented: $showsRestoreImporter, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do { try store.restore(from: url); restoreMessage = "バックアップを復元しました。" }
                catch { restoreMessage = "バックアップを読み込めませんでした。CarLogから書き出したJSONファイルを選択してください。" }
            case .failure:
                restoreMessage = "バックアップファイルを開けませんでした。"
            }
        }
        .alert("バックアップ復元", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) { Button("OK", role: .cancel) { restoreMessage = nil } } message: { Text(restoreMessage ?? "") }
    }

    private var chevron: some View { Image(systemName: "chevron.right").font(.headline).foregroundStyle(theme.deepAccent).frame(width: 12) }
    private func icon(_ symbol: String) -> some View { Image(systemName: symbol).font(.title3).foregroundStyle(theme.accent).frame(width: 42, height: 42).background(theme.softAccent, in: RoundedRectangle(cornerRadius: theme.controlRadius)) }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline).foregroundStyle(CarLogStyle.label); content() } }
    private func row(symbol: String, title: String, value: String?, action: @escaping () -> Void) -> some View { Button(action: action) { rowLabel(symbol: symbol, title: title, value: value) }.buttonStyle(.plain) }
    private func rowLabel(symbol: String, title: String, value: String?, showsChevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(CarLogStyle.label).lineLimit(1).minimumScaleFactor(0.7).frame(width: 116, alignment: .trailing)
            }
            if showsChevron { chevron } else { Color.clear.frame(width: 12, height: 1) }
        }
        .padding(.horizontal, 14).frame(minHeight: 70).contentShape(Rectangle())
    }
}

private struct BackupExport: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private extension View {
    func settingsCard() -> some View { self.background(Color(uiColor: .secondarySystemBackground).opacity(0.97), in: RoundedRectangle(cornerRadius: 14, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CarLogStyle.border, lineWidth: 1)) }
}

struct VehicleEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let existing: Vehicle?
    @State private var name: String
    @State private var nickname: String
    @State private var bodyType: BodyType
    @State private var fuelType: FuelType
    @State private var odometer: Double
    @State private var primaryColor: Color
    @State private var secondaryColor: Color
    @State private var twoTone: Bool
    @State private var mood: AppMood
    @State private var isPrimary: Bool
    @State private var showsColorPicker = false
    @State private var selectedPhoto: UIImage?
    @State private var photoWasChanged = false
    @State private var showsPhotoSource = false
    @State private var showsImagePicker = false
    @State private var imageSource: ImagePickerSource = .photoLibrary
    @State private var validationMessage: String?
    private var theme: CarLogTheme { CarLogTheme(mood: mood, colorScheme: colorScheme) }

    init(existing: Vehicle? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? ""); _nickname = State(initialValue: existing?.nickname ?? "")
        _bodyType = State(initialValue: existing?.bodyType ?? .compact); _fuelType = State(initialValue: existing?.fuelType ?? .regular)
        _odometer = State(initialValue: existing?.odometer ?? 0); _primaryColor = State(initialValue: Color(hex: existing?.primaryColorHex ?? "65B7EE"))
        _secondaryColor = State(initialValue: Color(hex: existing?.secondaryColorHex ?? "FFFFFF")); _twoTone = State(initialValue: existing?.secondaryColorHex != nil)
        _mood = State(initialValue: existing?.mood ?? .standard); _isPrimary = State(initialValue: existing?.isPrimary ?? false)
        _selectedPhoto = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 18) {
                    preview.frame(height: 245)
                    VStack(spacing: 0) {
                        fieldRow("車両名") { TextField("マイカー", text: $name) }
                        Divider(); fieldRow("愛称") { TextField("ソラ", text: $nickname) }
                        Divider(); fieldRow("オドメーター") { HStack { TextField("0", value: $odometer, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad); Text("Km") } }
                        Divider(); fieldRow("燃料種類") { Picker("", selection: $fuelType) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                        Divider()
                        Button { showsColorPicker = true } label: {
                            HStack { Text("ボディカラー").foregroundStyle(.primary); Spacer(); Circle().fill(primaryColor).frame(width: 32, height: 32); Text(twoTone ? "ツートン" : "選択中").foregroundStyle(.primary); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(.horizontal, 18).frame(height: 62)
                        }.buttonStyle(.plain)
                    }.settingsCard()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("雰囲気").font(.headline).foregroundStyle(CarLogStyle.label)
                        HStack(spacing: 8) { moodButton(.standard, symbol: "car.side", label: "スタンダード"); moodButton(.cool, symbol: "sunglasses", label: "クール"); moodButton(.cute, symbol: "heart", label: "キュート") }.padding(10).settingsCard()
                    }
                    Toggle(isOn: $isPrimary) {
                        VStack(alignment: .leading, spacing: 5) { Text("メイン車両").font(.headline); Text("ホームに表示する車両").font(.subheadline).foregroundStyle(CarLogStyle.label) }
                    }.tint(CarLogStyle.blue).carLogCard(padding: 18)
                    PrimaryActionButton(title: "変更を保存", action: save)
                    if let existing, store.data.vehicles.count > 1 {
                        Button("この車両を削除", role: .destructive) {
                            finishSaving(store.deleteVehicle(existing))
                        }.padding()
                    }
                }.padding(.horizontal, 18).padding(.vertical, 10).padding(.bottom, 24)
            }
        }
        .navigationTitle(existing == nil ? "車両を登録" : "車両を編集").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .sheet(isPresented: $showsColorPicker) { NavigationStack { BodyColorPickerView(primary: $primaryColor, secondary: $secondaryColor, twoTone: $twoTone, bodyType: bodyType) } }
        .sheet(isPresented: $showsImagePicker) { ImagePicker(source: imageSource) { selectedPhoto = $0; photoWasChanged = true } }
        .confirmationDialog("車両写真を変更", isPresented: $showsPhotoSource, titleVisibility: .visible) {
            Button("カメラで撮影") { imageSource = .camera; showsImagePicker = true }
            Button("写真ライブラリから選択") { imageSource = .photoLibrary; showsImagePicker = true }
            Button("キャンセル", role: .cancel) { }
        }
        .environment(\.carLogTheme, theme)
        .tint(theme.accent)
        .onAppear { if selectedPhoto == nil { selectedPhoto = AppStore.vehiclePhoto(filename: existing?.photoFilename) } }
        .alert("入力内容を確認してください", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
            Button("OK", role: .cancel) { validationMessage = nil }
        } message: { Text(validationMessage ?? "") }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardRadius).fill(LinearGradient(colors: [theme.softAccent, Color(uiColor: .secondarySystemBackground)], startPoint: .top, endPoint: .bottom))
                if let selectedPhoto { Image(uiImage: selectedPhoto).resizable().scaledToFill() }
                else { Image(systemName: bodyType.symbol).font(.system(size: 95)).foregroundStyle(primaryColor) }
            }.frame(width: 230, height: 180).clipShape(RoundedRectangle(cornerRadius: theme.cardRadius))
            Button(selectedPhoto == nil ? "写真を追加" : "写真を変更") { showsPhotoSource = true }.foregroundStyle(theme.accent)
        }
    }
    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View { HStack { Text(label).frame(width: 120, alignment: .leading); content(); Spacer() }.padding(.horizontal, 18).frame(minHeight: 62) }
    private func moodButton(_ value: AppMood, symbol: String, label: String) -> some View {
        let optionTheme = CarLogTheme(mood: value, colorScheme: colorScheme)
        return Button { mood = value } label: {
            VStack(spacing: 8) { Image(systemName: symbol).font(.title2); Text(label).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7) }
                .foregroundStyle(mood == value ? optionTheme.accent : CarLogStyle.label)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(mood == value ? optionTheme.softAccent : .clear, in: RoundedRectangle(cornerRadius: optionTheme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: optionTheme.controlRadius).stroke(mood == value ? optionTheme.accent : CarLogStyle.border))
        }.buttonStyle(.plain)
    }
    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let id = existing?.id ?? UUID()
        let photoFilename = photoWasChanged ? selectedPhoto.flatMap { store.saveVehiclePhoto($0, vehicleID: id) } : existing?.photoFilename
        let value = Vehicle(id: id, name: name, nickname: nickname, bodyType: bodyType, fuelType: fuelType, odometer: odometer, primaryColorHex: primaryColor.hexString(), secondaryColorHex: twoTone ? secondaryColor.hexString() : nil, mood: mood, isPrimary: isPrimary, createdAt: existing?.createdAt ?? Date(), photoFilename: photoFilename)
        finishSaving(existing == nil ? store.addVehicle(value) : store.updateVehicle(value))
    }

    private func finishSaving(_ saved: Bool) {
        if saved { dismiss() }
        else {
            validationMessage = store.lastError ?? "車両を保存できませんでした。"
            store.lastError = nil
        }
    }
}

struct BodyColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var primary: Color
    @Binding var secondary: Color
    @Binding var twoTone: Bool
    let bodyType: BodyType
    @State private var editingSecondary = false
    private let colors = [("ホワイト", "F7F7F5"), ("パール", "EBEAE6"), ("シルバー", "C6CBD0"), ("グレー", "878A8C"), ("ブラック", "161718"), ("ベージュ", "D8BE98"), ("ブラウン", "88513A"), ("レッド", "E01826"), ("ワイン", "980C2C"), ("オレンジ", "F28A13"), ("イエロー", "FFD928"), ("グリーン", "3D8D2F"), ("カーキ", "77795A"), ("ライトブルー", "65B7EE"), ("ブルー", "0862C6"), ("ネイビー", "17376C"), ("パープル", "7D53D5"), ("ピンク", "EC72A8")]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 14) {
                        ZStack { RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)); Image(systemName: bodyType.symbol).font(.system(size: 118)).foregroundStyle(editingSecondary ? secondary : primary) }.frame(height: 220)
                        HStack { Circle().fill(primary).frame(width: 32, height: 32); Text(twoTone ? "メイン × サブカラー" : "メインカラー").font(.headline) }
                        CarLogSegmentedPicker(labels: ["単色", "ツートン"], selection: Binding(get: { twoTone ? 1 : 0 }, set: { twoTone = $0 == 1 }))
                    }.carLogCard(padding: 12)
                    Text("編集するカラー").font(.title3.bold())
                    HStack(spacing: 10) {
                        target("メインカラー", color: primary, selected: !editingSecondary) { editingSecondary = false }
                        if twoTone { target("サブカラー", color: secondary, selected: editingSecondary) { editingSecondary = true } }
                    }
                    Text("カラーを選択").font(.title3.bold())
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 18) {
                        ForEach(colors, id: \.1) { item in
                            Button { setColor(Color(hex: item.1)) } label: {
                                VStack(spacing: 6) {
                                    ZStack { Circle().fill(Color(hex: item.1)).frame(width: 48, height: 48).overlay(Circle().stroke(Color.primary.opacity(0.16))); if selectedHex == item.1 { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(CarLogStyle.blue).background(Color(uiColor: .systemBackground), in: Circle()) } }
                                    Text(item.0).font(.system(size: 9)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.55)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    ColorPicker(selection: customBinding, supportsOpacity: false) { HStack { Image(systemName: "paintpalette.fill").foregroundStyle(CarLogStyle.blue); Text("その他のカラー").font(.headline) } }.carLogCard(padding: 16)
                    PrimaryActionButton(title: "このカラーに設定") { dismiss() }
                }.padding(18).padding(.bottom, 24)
            }
        }
        .navigationTitle("ボディカラー").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
    }
    private var selectedHex: String { (editingSecondary ? secondary : primary).hexString() }
    private var customBinding: Binding<Color> { editingSecondary ? $secondary : $primary }
    private func setColor(_ color: Color) { if editingSecondary { secondary = color } else { primary = color } }
    private func target(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Circle().fill(color).frame(width: 42, height: 42).overlay(Circle().stroke(Color.black.opacity(0.1))); Text(title).font(.caption.bold()); Spacer() }.padding(10).background(selected ? CarLogStyle.softBlue : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? CarLogStyle.blue : CarLogStyle.border, lineWidth: selected ? 2 : 1)) }.buttonStyle(.plain)
    }
}

struct DriverManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingDriver: DriverProfile?

    var body: some View {
        List {
            Section {
                ForEach(store.activeDrivers) { profile in
                    Button { editingDriver = profile } label: {
                        HStack {
                            Circle().fill(profile.color).frame(width: 14, height: 14)
                            Text(profile.name).foregroundStyle(.primary)
                            Spacer()
                            if profile.id == DriverProfile.mainID { Text("メイン").foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("ユーザーを追加", systemImage: "person.badge.plus") {
                    editingDriver = DriverProfile(name: "", colorHex: "FF9500")
                }
            } footer: {
                Text("以前の走行記録は「自分」に引き継がれます。任意の名前で記録した距離は「その他」に合算されます。")
            }
            if store.drivers.contains(where: \.isArchived) {
                Section("選択候補から外したユーザー") {
                    ForEach(store.drivers.filter(\.isArchived)) { profile in
                        Button { editingDriver = profile } label: {
                            HStack {
                                Circle().fill(profile.color).frame(width: 14, height: 14)
                                Text(profile.name)
                                Spacer()
                                Text("編集して再追加").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink("ユーザー別の走行距離") { DriverMileageView() }
            }
        }
        .navigationTitle("ユーザー管理").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editingDriver) { profile in
            NavigationStack { DriverEditorView(profile: profile) }
        }
    }
}

private struct DriverEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let profile: DriverProfile
    @State private var name: String
    @State private var color: Color
    @State private var error: String?
    @State private var showsArchiveConfirmation = false

    init(profile: DriverProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _color = State(initialValue: profile.color)
    }

    var body: some View {
        Form {
            Section {
                TextField("ユーザー名", text: $name).disabled(profile.id == DriverProfile.otherID)
                ColorPicker("ラベルカラー", selection: $color, supportsOpacity: false)
            }
            if profile.id == DriverProfile.otherID {
                Section { Text("任意の名前で記録したユーザーには、この共通カラーを使います。").foregroundStyle(.secondary) }
            }
            if store.drivers.contains(where: { $0.id == profile.id }),
               profile.id != DriverProfile.mainID, profile.id != DriverProfile.otherID {
                Section {
                    Button("選択候補から外す", role: .destructive) { showsArchiveConfirmation = true }
                } footer: { Text("過去の走行記録・距離・色は残ります。") }
            }
        }
        .navigationTitle("ユーザーを編集").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(archived: false) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("このユーザーを選択候補から外しますか？", isPresented: $showsArchiveConfirmation, titleVisibility: .visible) {
            Button("選択候補から外す", role: .destructive) { save(archived: true) }
        }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(error ?? "") }
    }

    private func save(archived: Bool) {
        var value = profile
        value.name = name
        value.colorHex = color.hexString()
        value.isArchived = archived
        if store.saveDriver(value) { dismiss() }
        else { error = store.lastError; store.lastError = nil }
    }
}

struct DriverMileageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var vehicleID: UUID?
    @State private var month = Date().startOfMonth
    @State private var period = 0

    private var interval: DateInterval? {
        switch period {
        case 0: return Calendar.current.dateInterval(of: .month, for: month)
        case 1: return Calendar.current.dateInterval(of: .year, for: month)
        default: return nil
        }
    }

    var body: some View {
        let totals = store.driverDistances(vehicleID: vehicleID, interval: interval)
        let total = totals.reduce(0) { $0 + $1.distance }
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Picker("車両", selection: $vehicleID) {
                        Text("全車両").tag(nil as UUID?)
                        ForEach(store.data.vehicles) { car in
                            Text(car.nickname.isEmpty ? car.name : car.nickname).tag(Optional(car.id))
                        }
                    }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).carLogCard(padding: 12)
                    Picker("表示期間", selection: $period) {
                        Text("月間").tag(0); Text("年間").tag(1); Text("全期間").tag(2)
                    }.pickerStyle(.segmented)
                    if period == 0 { MonthNavigator(month: $month) }
                    if period == 1 {
                        HStack {
                            Button { moveYear(-1) } label: { Image(systemName: "chevron.left").padding(10) }
                            Spacer()
                            Text(month, format: .dateTime.year()).font(.title2.bold())
                            Spacer()
                            Button { moveYear(1) } label: { Image(systemName: "chevron.right").padding(10) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("合計走行距離").foregroundStyle(.secondary)
                        Text(total.formatted(.number.precision(.fractionLength(0...1))) + " km").font(.largeTitle.bold())
                        ForEach(totals) { item in
                            VStack(spacing: 6) {
                                HStack {
                                    Circle().fill(item.driver.color).frame(width: 12, height: 12)
                                    Text(item.driver.name + (item.driver.isArchived ? "（選択候補外）" : ""))
                                    Spacer()
                                    Text(item.distance.formatted(.number.precision(.fractionLength(0...1))) + " km").monospacedDigit()
                                }
                                GeometryReader { proxy in
                                    Capsule().fill(item.driver.color.opacity(0.12))
                                    Capsule().fill(item.driver.color).frame(width: total > 0 ? proxy.size.width * item.distance / total : 0)
                                }.frame(height: 6)
                            }
                        }
                    }.carLogCard()
                    Text("車両を切り替えると、車両ごとのユーザー走行距離を確認できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }
        }
        .navigationTitle("ユーザー別の走行距離").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
    private func moveYear(_ value: Int) {
        if let date = Calendar.current.date(byAdding: .year, value: value, to: month) { month = date }
    }

}
