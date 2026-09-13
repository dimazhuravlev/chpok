import SwiftUI

/// Full-screen dimmed overlay with a score/bonus/total card, shown when the
/// engine reports game over (win or loss).
struct GameOverOverlay: View {
    let info: GameOverInfo
    let onOK: () -> Void

    var body: some View {
        ZStack {
            Color(Palette.overlayScrim).ignoresSafeArea()

            VStack(spacing: 12) {
                Text(info.title)
                    .font(.title.bold())
                    .accessibilityIdentifier("gameOverTitle")
                Text("Score: \(info.score)")
                Text("Bonus: \(info.bonus)")
                Text("Total: \(info.total)")
                    .accessibilityIdentifier("gameOverTotal")
                Button("OK") { onOK() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("okButton")
            }
            .padding(24)
            .foregroundStyle(.white)
            .background(Color(Palette.overlayCard))
            .cornerRadius(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gameOverOverlay")
        }
    }
}
