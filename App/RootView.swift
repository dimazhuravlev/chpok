import SwiftUI
import SpriteKit

struct RootView: View {
    @StateObject var vm = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var paletteStore = PaletteStore.shared
    /// Debug entry point: launching with `-showGameOverDemo` shows
    /// `GameOverScreen` immediately with sample data — the "win with a new
    /// record" mockup of spec 36 (score 45062, time 05:21, previous best
    /// 08:32) — so the fullscreen game-over look can be eyeballed without
    /// playing a match to the end. Tapping "new game" clears it and falls
    /// through to the normal game, same as a real game over.
    @State private var showGameOverDemo = CommandLine.arguments.contains("-showGameOverDemo")
    /// Shown on shake (spec 32), but only during active play — the palette
    /// sheet has no business appearing over the game-over screen, which has
    /// its own dedicated full-screen presentation and transition.
    @State private var showPaletteSheet = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HUDView(score: vm.score, livesLeft: vm.livesLeft, maxLives: vm.maxLives, onRestart: vm.restart)
                GeometryReader { geo in
                    ZStack {
                        if let scene = vm.scene {
                            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                        } else {
                            Color(Palette.background)
                        }
                        Rectangle()
                            .fill(.clear)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("gameScene")
                            .accessibilityValue(vm.status)
                    }
                    // Extra gap above the board so the first bubble row lands
                    // 42.5pt below the header (see GameViewModel.sceneTopInset).
                    // Reducing the *height* passed to `prepare` by the same
                    // amount keeps the rendered scene's bottom edge flush with
                    // this GeometryReader's own bottom, so the cannon/queue
                    // bubbles still land at their absolute Figma positions.
                    .padding(.top, GameViewModel.sceneTopInset(areaWidth: Double(geo.size.width)))
                    .onAppear {
                        Haptics.shared.prepareForButton()
                        vm.prepare(containerSize: sceneContainerSize(for: geo.size))
                    }
                    .onChange(of: geo.size) { vm.prepare(containerSize: sceneContainerSize(for: $0)) }
                }
                .padding(.horizontal, 10)
            }
            .ignoresSafeArea(edges: .bottom)
            // Own opacity, driven by `GameViewModel.gameOpacity` (spec 31):
            // zero while the game-over screen is up, animated back to one
            // by `dismissGameOver()` only after that screen has fully faded
            // out, so the two screens never show through each other.
            .opacity(vm.gameOpacity)

            if showGameOverDemo {
                GameOverScreen(
                    info: GameOverInfo(won: true, score: 45062, bonus: 0, elapsedMs: 321_000, previousBestMs: 512_000),
                    onNewGame: { withAnimation(.easeInOut(duration: GameViewModel.gameOverFadeDuration)) { showGameOverDemo = false } }
                )
                .transition(.opacity)
            } else if let info = vm.gameOver {
                GameOverScreen(info: info, onNewGame: vm.dismissGameOver)
                    .transition(.opacity)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { if $0 != .active { vm.persistIfPossible() } }
        // Live repaint (spec 32 step 3): whenever the palette changes, push
        // the new colors onto every bubble node that already exists instead
        // of waiting for them to be recreated.
        .onChange(of: paletteStore.colors) { _ in vm.scene?.repaintBubbles() }
        .onShake {
            guard vm.gameOver == nil else { return }
            showPaletteSheet = true
        }
        .sheet(isPresented: $showPaletteSheet) {
            PaletteSheet()
        }
    }

    private func sceneContainerSize(for areaSize: CGSize) -> CGSize {
        let inset = GameViewModel.sceneTopInset(areaWidth: Double(areaSize.width))
        return CGSize(width: areaSize.width, height: max(areaSize.height - inset, 0))
    }
}

#Preview {
    RootView()
}
