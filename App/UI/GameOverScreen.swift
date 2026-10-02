import SwiftUI
import BubbleShooterCore

/// Full-screen game-over screen (spec 26, reworked to the owner's mockups in
/// spec 36): the background pulses through all six bubble colors, and the
/// content is the win/lose title at the top, the new-game button at the
/// bottom and — on a win only — the result lines at the center of the screen:
/// `score N`, then the time (`new best time` when this match set the personal
/// best, plain `time` otherwise), then the *previous* best muted underneath
/// for comparison (nothing when there was none). A loss shows only the title
/// and the button. All text is white: the mockups set it that way, trading the
/// readability spec 26 bought with black text (white is ~1.7:1 on the lighter
/// palette colors) for the look the owner drew.
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

    // Result lines (spec 36 mockups). In the mockups the tops of the letters
    // are 56pt apart from the score line to the time line and 34pt apart from
    // the time line to the previous-best line, so the previous best is tucked
    // up against the time. Pretendard-SemiBold at 32pt sets a 38.19pt line, so
    // for the second pair that is a *negative* stack spacing. The first pair
    // is 0.78pt more than 56 between baselines: the dot of the "i" that tops
    // the lines below stands 0.78pt higher than the tallest digits of the
    // score line.
    /// Gap between the score line and the time line.
    private static let scoreToTimeSpacing: CGFloat = 18.6
    /// Gap between the time line and the previous-best line (negative: see above).
    private static let timeToBestSpacing: CGFloat = -4.2
    /// Opacity of the white the previous-best line is set in (mockup: 0.40).
    private static let previousBestOpacity: Double = 0.4

    var body: some View {
        ZStack {
            Color(uiColor: Palette.color(for: Self.colors[colorIndex]))
                .ignoresSafeArea()

            VStack {
                Text(info.title)
                    .font(.pretendardSemiBold(32))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("gameOverTitle")
                    .padding(.top, Self.titleTopPadding)

                Spacer()

                Button("new game") {
                    Haptics.shared.buttonTapped()
                    onNewGame()
                }
                .font(.pretendardSemiBold(32))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .accessibilityIdentifier("okButton")
                .padding(.bottom, 32)
            }

            // A loss leaves the middle of the screen empty (spec 36).
            if info.won {
                resultLines
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

    /// Score, time and previous best, centered on the screen itself — the
    /// mockups have the block at the exact vertical center of the display, so
    /// it ignores the safe areas instead of being centered between the title
    /// and the button (which would sit it ~22pt low: the top and bottom
    /// insets and paddings are not symmetric). Labels only, so it never
    /// intercepts taps meant for the button underneath.
    private var resultLines: some View {
        VStack(spacing: Self.scoreToTimeSpacing) {
            Text(verbatim: "score \(info.total)")
                .accessibilityIdentifier("gameOverTotal")
            VStack(spacing: Self.timeToBestSpacing) {
                Text(verbatim: "\(info.timeLabel) \(info.timeText)")
                    .accessibilityIdentifier("gameOverTime")
                // The best as it was before this match, for comparison; no
                // record yet means no line at all, not a placeholder.
                if let bestText = info.bestText {
                    Text(verbatim: "best time \(bestText)")
                        .foregroundStyle(Color.white.opacity(Self.previousBestOpacity))
                        .accessibilityIdentifier("gameOverBest")
                }
            }
        }
        .font(.pretendardSemiBold(32))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
