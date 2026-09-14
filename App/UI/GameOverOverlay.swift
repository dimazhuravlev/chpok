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
                    .font(.pretendardSemiBold(28))
                    .accessibilityIdentifier("gameOverTitle")
                Text("Score: \(info.score)")
                    .font(.pretendardSemiBold(17))
                Text("Bonus: \(info.bonus)")
                    .font(.pretendardSemiBold(17))
                Text("Total: \(info.total)")
                    .font(.pretendardSemiBold(17))
                    .accessibilityIdentifier("gameOverTotal")
                Text("Time: \(info.timeText)")
                    .font(.pretendardSemiBold(17))
                    .accessibilityIdentifier("gameOverTime")
                Button("OK") { onOK() }
                    .font(.pretendardSemiBold(17))
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
