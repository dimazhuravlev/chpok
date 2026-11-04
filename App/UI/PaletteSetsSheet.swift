import SwiftUI

/// Test bottom sheet with every ready-made palette set (spec 56), opened by a
/// long press on the score or the `-showPaletteSets` launch argument. Each
/// row is a set's name and a tile in the set's own background with its six
/// colors as circles, flush like on the board; tapping a row applies the set
/// at once, so the board behind the sheet repaints live. At the medium detent
/// the board stays undimmed and playable, so the colors can be judged as they
/// really look.
struct PaletteSetsSheet: View {
    @ObservedObject private var store = PaletteStore.shared

    private static let circleSize: CGFloat = 28

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                section("dark", sets: PaletteSet.all.filter { !$0.isLight })
                section("light", sets: PaletteSet.all.filter { $0.isLight })
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier("paletteSetsSheet")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section(_ title: String, sets: [PaletteSet]) -> some View {
        Text(verbatim: title)
            .font(.appSemiBold(14))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 8)
        ForEach(sets) { set in
            row(set)
        }
    }

    private func row(_ set: PaletteSet) -> some View {
        let isSelected = store.selectedSetId == set.id
        return Button {
            Haptics.shared.selectionChanged()
            store.apply(set)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: set.name)
                    .font(.appSemiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    ForEach(set.colors.indices, id: \.self) { i in
                        Circle()
                            .fill(Color(uiColor: UIColor(hex: set.colors[i])))
                            .frame(width: Self.circleSize, height: Self.circleSize)
                    }
                }
                .padding(8)
                .background(Color(uiColor: UIColor(hex: set.background)), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? .white : .clear, lineWidth: 2)
                        .padding(-2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paletteSet.\(set.id)")
    }
}
