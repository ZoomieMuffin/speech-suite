import SwiftUI

/// Push-to-Talk 録音中に表示するフローティングオーバーレイのコンテンツ。
/// モード名・録音インジケータ・音声レベルメーターを最小限に表示する。
struct OverlayView: View {
    let appState: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Text(modeLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 1.0 : 0.25)

            LevelMeterView(level: appState.audioLevel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var modeLabel: String {
        switch appState.status {
        case .recording(.insert), .transcribing(.insert): return "Insert"
        case .recording(.dvn),    .transcribing(.dvn):    return "Voice Note"
        default:                                           return ""
        }
    }
}

/// 水平レベルメーター。level は 0.0〜1.0 で指定する。
private struct LevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.3))
                Capsule()
                    .fill(level > 0.75 ? Color.red : Color.green)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, level))))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(width: 80, height: 6)
    }
}
