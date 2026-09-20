import SwiftUI

struct ReclaimAdviceList: View {
    let advice: [ReclaimAdvice]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reclaim advisor").font(.headline)
            Text("Classifies measured paths so you can see what is safe to clean, what needs review, and what must stay. This is the Hostwatch subset of that workflow — it never deletes protected data.").font(.footnote).foregroundStyle(HW.secondary)
            if advice.isEmpty {
                Text("No measured paths to classify yet.").font(.caption).foregroundStyle(HW.secondary)
            }
            ForEach(advice.sorted { $0.bytes > $1.bytes }) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.className.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(ReclaimPolicy.color(for: item.className).opacity(0.16))
                            .foregroundStyle(ReclaimPolicy.color(for: item.className))
                            .clipShape(Capsule())
                        Spacer()
                        Text(Format.bytes(item.bytes)).font(.subheadline.monospacedDigit())
                    }
                    Text(item.path).font(.hw(.caption, design: .monospaced, weight: .semibold)).textSelection(.enabled)
                    Text(item.reason).font(.caption).foregroundStyle(HW.secondary)
                }.padding(14).panel()
            }
        }
    }
}
