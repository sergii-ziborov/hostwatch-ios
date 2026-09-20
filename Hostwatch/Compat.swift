import SwiftUI
import UIKit

struct HWStackNavigation<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

struct HWLabeled: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

struct HWSeries: Identifiable {
    let id: String
    let color: Color
    let values: [Double]
    var filled = false
}

struct HWLineChart: View {
    let dates: [Date]
    let series: [HWSeries]
    var yMax: Double?
    var height: CGFloat = 220

    var body: some View {
        let peak = max(yMax ?? series.flatMap(\.values).max() ?? 1, 1)
        let count = max(series.map(\.values.count).max() ?? 1, 2)
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let inset = CGRect(x: 6, y: 6, width: max(1, size.width - 12), height: max(1, size.height - 12))
                for step in 0...4 {
                    let y = inset.minY + inset.height * CGFloat(step) / 4
                    var grid = Path()
                    grid.move(to: CGPoint(x: inset.minX, y: y))
                    grid.addLine(to: CGPoint(x: inset.maxX, y: y))
                    context.stroke(grid, with: .color(HW.border.opacity(0.45)), lineWidth: 0.5)
                }
                for serie in series {
                    guard serie.values.count > 1 else { continue }
                    var path = Path()
                    for (index, value) in serie.values.enumerated() {
                        let x = inset.minX + inset.width * CGFloat(index) / CGFloat(count - 1)
                        let y = inset.maxY - inset.height * CGFloat(min(value, peak) / peak)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    if serie.filled {
                        var fill = path
                        fill.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
                        fill.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
                        fill.closeSubpath()
                        context.fill(fill, with: .color(serie.color.opacity(0.28)))
                    }
                    context.stroke(path, with: .color(serie.color), lineWidth: 2)
                }
            }
            .frame(height: height)
            if let first = dates.first, let last = dates.last {
                HStack {
                    Text(first.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(HW.secondary)
            }
        }
    }
}

extension Font {
    static func hw(_ style: TextStyle, design: Design = .default, weight: Weight = .regular) -> Font {
        .system(style, design: design).weight(weight)
    }
}

enum HWSleep {
    static func milliseconds(_ value: UInt64) async {
        try? await Task.sleep(nanoseconds: value * 1_000_000)
    }

    static func seconds(_ value: UInt64) async {
        try? await Task.sleep(nanoseconds: value * 1_000_000_000)
    }
}

extension View {
    @ViewBuilder
    func hwHiddenScrollBackground() -> some View {
        if #available(iOS 16, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func hwSheetDetents() -> some View {
        if #available(iOS 16, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}

enum HWAppearance {
    static func apply() {
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }
}
