import SwiftUI
import SpriteKit

struct RootView: View {
    @StateObject var vm = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
                    .onAppear { vm.prepare(containerSize: sceneContainerSize(for: geo.size)) }
                    .onChange(of: geo.size) { vm.prepare(containerSize: sceneContainerSize(for: $0)) }
                }
                .padding(.horizontal, 10)
            }
            .ignoresSafeArea(edges: .bottom)

            if let info = vm.gameOver {
                GameOverOverlay(info: info, onOK: vm.dismissGameOver)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { if $0 != .active { vm.persistIfPossible() } }
    }

    private func sceneContainerSize(for areaSize: CGSize) -> CGSize {
        let inset = GameViewModel.sceneTopInset(areaWidth: Double(areaSize.width))
        return CGSize(width: areaSize.width, height: max(areaSize.height - inset, 0))
    }
}

#Preview {
    RootView()
}
