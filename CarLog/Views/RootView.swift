import SwiftUI

struct RootView: View {
    private enum PresentedSheet: String, Identifiable {
        case vehicleSetup, trip, fuel
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var quickActionRouter = QuickActionRouter.shared
    @State private var selectedTab = 0
    @State private var analyticsMetric = 0
    @State private var presentedSheet: PresentedSheet?
    private var theme: CarLogTheme { CarLogTheme(mood: store.selectedVehicle?.mood ?? .standard, colorScheme: colorScheme) }
    var body: some View {
        ZStack {
            ScreenBackground()
            if store.hasVehicles {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        HomeView(
                            openAnalytics: { metric in
                                analyticsMetric = metric
                                selectedTab = 2
                            },
                            openRecord: { destination in
                                presentedSheet = destination == .trip ? .trip : .fuel
                            }
                        )
                    }.tabItem { Label("ホーム", systemImage: "house.fill") }.tag(0)
                    NavigationStack { RecordsView() }.tabItem { Label("履歴", systemImage: "clock.fill") }.tag(1)
                    NavigationStack { AnalyticsView(metric: $analyticsMetric) }.tabItem { Label("分析", systemImage: "chart.bar.fill") }.tag(2)
                    NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(3)
                }
            } else { WelcomeView { presentedSheet = .vehicleSetup } }
        }
        .environment(\.carLogTheme, theme)
        .tint(theme.accent)
        .sheet(item: $presentedSheet) { destination in
            NavigationStack {
                switch destination {
                case .vehicleSetup:
                    VehicleEditorView()
                case .trip:
                    if let vehicle = store.selectedVehicle {
                        TripEditorView(vehicleID: vehicle.id)
                    }
                case .fuel:
                    if let vehicle = store.selectedVehicle {
                        FuelEditorView(vehicleID: vehicle.id)
                    }
                }
            }
        }
        .onOpenURL(perform: openDeepLink)
        .onAppear {
            QuickActionSceneBridge.install()
            openPendingQuickAction()
        }
        .onChange(of: quickActionRouter.pendingDestination) { _, _ in
            openPendingQuickAction()
        }
        .alert("エラー", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) { Button("閉じる", role: .cancel) { store.lastError = nil } } message: { Text(store.lastError ?? "") }
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme == "carlog", url.host == "record" else { return }
        guard store.hasVehicles else {
            presentedSheet = .vehicleSetup
            return
        }
        selectedTab = 0
        switch url.pathComponents.last {
        case "trip": presentedSheet = .trip
        case "fuel": presentedSheet = .fuel
        default: break
        }
    }

    private func openPendingQuickAction() {
        guard let destination = quickActionRouter.pendingDestination else { return }
        quickActionRouter.consume()
        guard store.hasVehicles else {
            presentedSheet = .vehicleSetup
            return
        }
        selectedTab = 0
        presentedSheet = destination == .trip ? .trip : .fuel
    }
}

private struct WelcomeView: View {
    let start: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.side.fill").font(.system(size: 70)).foregroundStyle(CarLogStyle.blue)
            Text("カーログ").font(.largeTitle.bold())
            Text("走行距離と給油を、かんたんに記録。\nあなたのカーライフを見える化します。").multilineTextAlignment(.center).foregroundStyle(CarLogStyle.label)
            PrimaryActionButton(title: "最初の車両を登録", action: start).padding(.horizontal, 36)
        }
    }
}
