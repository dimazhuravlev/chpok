import SwiftUI

/// Test bottom sheet with every ready-made palette set (spec 56), opened by a
/// long press on the score or the `-showPaletteSets` launch argument. On top,
/// pinned, the dark/light theme switch (spec 57); below it a scrolling list
/// where each row is a set's name and a tile in the set's background with its
/// six colors as circles, flush like on the board — both as the current theme
/// shows them. Tapping a row applies the set at once, so the board behind the
/// sheet repaints live. The sheet stays at half height with the list
/// scrolling inside it, so the board stays undimmed and playable above it and
/// the colors can be judged as they really look.
struct PaletteSetsSheet: View {
    @ObservedObject private var store = PaletteStore.shared

    private static let circleSize: CGFloat = 28

    private var isLight: Bool { store.appearance == .light }

    var body: some View {
        VStack(spacing: 0) {
            Picker("theme", selection: appearance) {
                Text(verbatim: "dark").tag(PaletteStore.Appearance.dark)
                Text(verbatim: "light").tag(PaletteStore.Appearance.light)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearancePicker")
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(PaletteSet.all) { set in
                        row(set)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("paletteSetsSheet")
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .preferredColorScheme(isLight ? .light : .dark)
    }

    private var appearance: Binding<PaletteStore.Appearance> {
        Binding(
            get: { store.appearance },
            set: { newValue in
                Haptics.shared.selectionChanged()
                store.setAppearance(newValue)
            }
        )
    }

    /// A color of the set as the current theme shows it.
    private func shown(_ hex: UInt32) -> Color {
        Color(uiColor: Palette.display(isLight ? LightTheme.color(for: hex) : hex))
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
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    ForEach(set.colors.indices, id: \.self) { i in
                        Circle()
                            .fill(shown(set.colors[i]))
                            .frame(width: Self.circleSize, height: Self.circleSize)
                    }
                }
                .padding(8)
                .background(shown(set.background), in: RoundedRectangle(cornerRadius: 12))
                // In the light theme the white tile sits on the sheet's own
                // white; a hairline keeps its edge.
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.black.opacity(isLight ? 0.1 : 0), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.primary : .clear, lineWidth: 2)
                        .padding(-2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paletteSet.\(set.id)")
    }
}
