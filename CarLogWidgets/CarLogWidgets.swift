import SwiftUI
import WidgetKit

private struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

private struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry { QuickRecordEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        completion(Timeline(entries: [QuickRecordEntry(date: Date())], policy: .never))
    }
}

private struct QuickRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let symbol: String
    let destination: URL

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(title, systemImage: symbol)
            case .accessoryCircular:
                Image(systemName: symbol)
                    .font(.title2.bold())
                    .widgetAccentable()
            default:
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title2.bold())
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text("記録画面へ").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(destination)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TripRecordWidget: Widget {
    let kind = "TripRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView(
                title: "距離",
                symbol: "road.lanes",
                destination: URL(string: "carlog://record/trip")!
            )
        }
        .configurationDisplayName("走行記録を記録")
        .description("走行距離の記録画面をすぐに開きます。")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct FuelRecordWidget: Widget {
    let kind = "FuelRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView(
                title: "給油",
                symbol: "fuelpump.fill",
                destination: URL(string: "carlog://record/fuel")!
            )
        }
        .configurationDisplayName("給油記録")
        .description("給油記録の入力画面をすぐに開きます。")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct CarLogWidgets: WidgetBundle {
    var body: some Widget {
        TripRecordWidget()
        FuelRecordWidget()
    }
}
