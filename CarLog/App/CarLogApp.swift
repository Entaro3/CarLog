import SwiftUI
import UIKit

enum QuickActionDestination: String {
    case trip = "jp.WisGlide.CarLog.record.trip"
    case fuel = "jp.WisGlide.CarLog.record.fuel"
}

final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()

    @Published private(set) var pendingDestination: QuickActionDestination?

    @discardableResult
    func route(shortcutType: String) -> Bool {
        guard let destination = QuickActionDestination(rawValue: shortcutType) else { return false }
        pendingDestination = destination
        return true
    }

    func consume() {
        pendingDestination = nil
    }
}

final class CarLogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = connectionOptions.shortcutItem {
            QuickActionRouter.shared.route(shortcutType: shortcutItem.type)
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}

final class QuickActionSceneDelegateProxy: NSObject, UIWindowSceneDelegate {
    private let originalDelegate: UISceneDelegate

    init(originalDelegate: UISceneDelegate) {
        self.originalDelegate = originalDelegate
        super.init()
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActionRouter.shared.route(shortcutType: shortcutItem.type))
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || originalDelegate.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if originalDelegate.responds(to: aSelector) {
            return originalDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

@MainActor
enum QuickActionSceneBridge {
    static func install() {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let delegate = windowScene.delegate,
                  !(delegate is QuickActionSceneDelegateProxy) else { continue }
            windowScene.delegate = QuickActionSceneDelegateProxy(originalDelegate: delegate)
        }
    }
}

@main
struct CarLogApp: App {
    @UIApplicationDelegateAdaptor(CarLogAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // 車体色は白など操作文字に不向きな色も選べるため、
                // システムボタンの色には使用しない。
                .tint(CarLogStyle.blue)
                .preferredColorScheme(store.appearanceMode.colorScheme)
        }
    }
}
