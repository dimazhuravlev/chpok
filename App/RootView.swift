import SwiftUI
import SpriteKit

struct RootView: View {
    @StateObject var vm = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HUDView(score: vm.score, onRestart: vm.restart)
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
                    .onAppear { vm.prepare(containerSize: geo.size) }
                    .onChange(of: geo.size) { vm.prepare(containerSize: $0) }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if let info = vm.gameOver {
                GameOverOverlay(info: info, onOK: vm.dismissGameOver)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .onChange(of: scenePhase) { if $0 != .active { vm.persistIfPossible() } }
    }
}

#Preview {
    RootView()
}
