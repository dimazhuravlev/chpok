import SwiftUI
import BubbleShooterCore

/// Full-screen game-over screen (spec 26): the background pulses through all
/// six bubble colors, and the content is three parts top to bottom — the
/// win/lose title, the total score and match time centered, and the
/// new-game button. Text and the button are black, not white — white reads
/// at ~1.7:1 contrast on the lighter palette colors (orange, cyan, lime)
/// while black reads at 4.7:1–12.2:1 on every color, and it inverts the
/// in-game white-on-black look for a distinct final beat.
struct GameOverScreen: View {
    let info: GameOverInfo
    let onNewGame: () -> Void

    @State private var colorIndex = 0
    @State private var timer: Timer?

    private static let colors = BubbleColor.allCases
    // Background color-cycling timing — tweak both together, one edit each.
    /// How long a color stays fully settled before crossfading to the next.
    private static let pureHoldDuration: TimeInterval = 0.3
    /// How long the crossfade to the next color takes (kept < `stepInterval`
    /// so every step spends part of its time on a pure palette color instead
    /// of always mid-blend).
    private static let transitionDuration: TimeInterval = 0.2
    /// Time between color steps; a full six-color loop takes 6x this.
    private static let stepInterval = pureHoldDuration + transitionDuration
    /// Top padding for the title, from the top safe area — one grid step
    /// (32pt) below the HUD header's own 16pt so it clears the camera
    /// cutout instead of pressing against it.
    private static let titleTopPadding: CGFloat = 48

    var body: some View {
        ZStack {
            Color(uiColor: Palette.color(for: Self.colors[colorIndex]))
                .ignoresSafeArea()

            VStack {
                Text(info.title)
                    .font(.pretendardSemiBold(32))
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("gameOverTitle")
                    .padding(.top, Self.titleTopPadding)

                Spacer()

                VStack(spacing: 8) {
                    Text(verbatim: "score \(info.total)")
                        .accessibilityIdentifier("gameOverTotal")
                    Text("time \(info.timeText)")
                        .accessibilityIdentifier("gameOverTime")
                }
                .font(.pretendardSemiBold(32))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)

                Spacer()

                Button("new game") {
                    Haptics.shared.buttonTapped()
                    onNewGame()
                }
                .font(.pretendardSemiBold(32))
                .foregroundStyle(.black)
                .buttonStyle(.plain)
                .accessibilityIdentifier("okButton")
                .padding(.bottom, 32)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gameOverOverlay")
        .onAppear {
            Haptics.shared.prepareForButton()
            startCycling()
        }
        .onDisappear(perform: stopCycling)
    }

    private func startCycling() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.stepInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: Self.transitionDuration)) {
                colorIndex = (colorIndex + 1) % Self.colors.count
            }
        }
    }

    private func stopCycling() {
        timer?.invalidate()
        timer = nil
    }
}
