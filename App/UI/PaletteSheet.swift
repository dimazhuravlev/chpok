import SwiftUI
import UIKit
import BubbleShooterCore

/// Reports the natural (unconstrained) height of whatever it's attached to
/// via `.background(GeometryReader { ... })` — the measurement half of the
/// "sheet sized to its content" workaround below.
private struct PaletteSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Bottom sheet for customizing bubble colors (spec 32), opened by shaking
/// the device (see `ShakeDetector`/`RootView`). Six circles, each filled
/// with its slot's current color; tapping one opens the system color picker
/// so the player can replace it. `reset colors` restores the original six.
/// Chrome (background material, corner rounding, drag indicator) is the
/// system default for a sheet — nothing custom-drawn on top of it, and
/// dismissal is the standard swipe-down/drag-indicator gesture only.
///
/// Sizing: iOS 17 has no built-in "fit to content" `presentationDetents`
/// case, so the content measures its own height once (`.fixedSize(vertical:
/// true)` forces SwiftUI to ask for the ideal height instead of stretching
/// to fill the sheet, and the `.background(GeometryReader...)` +
/// `PaletteSheetHeightKey` pair reads that ideal size back out) and feeds it
/// into `.presentationDetents([.height(...)])`. The measurement is taken
/// exactly once per presentation and then left alone — see `contentHeight`.
struct PaletteSheet: View {
    @ObservedObject private var store = PaletteStore.shared
    /// Fallback used for the first frame, before the real content height has
    /// been measured — close to the actual measured height so there's no
    /// visible jump.
    @State private var contentHeight: CGFloat = 380
    /// Set the first time `contentHeight` is assigned a real measurement,
    /// and never again for this presentation of the sheet (owner feedback):
    /// re-deriving the detent on every layout pass — including the ones
    /// triggered by presenting the color picker on top — was what made the
    /// sheet visibly jiggle. The six circles and the button never change
    /// shape once laid out, so one measurement is all this ever needs; a
    /// fresh presentation gets a fresh `PaletteSheet` (and thus a fresh
    /// `false` here) to re-measure from scratch.
    @State private var hasMeasuredHeight = false

    /// Grid order per the mockup, left-to-right/top-to-bottom: blue, lime
    /// (green), coral (red), lilac (purple), terracotta (lightblue), orange
    /// (yellow) — not `BubbleColor.allCases`' own declaration order.
    private static let displayOrder: [BubbleColor] = [.blue, .green, .red, .purple, .lightblue, .yellow]

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    var body: some View {
        VStack(spacing: 0) {
            grid
                .padding(.top, 24)

            Button("reset colors") {
                Haptics.shared.buttonTapped()
                store.resetToDefaults()
            }
            .font(.pretendardSemiBold(32))
            .tint(.white)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            // Dimmed when there's nothing to reset (owner feedback); still
            // tappable — resetting an already-default palette to itself is
            // harmless, so disabling it isn't worth the extra state.
            .opacity(store.isDefault ? 0.3 : 1.0)
            .accessibilityIdentifier("resetPaletteButton")
            .padding(.top, 32)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PaletteSheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PaletteSheetHeightKey.self) { height in
            guard height > 0, !hasMeasuredHeight else { return }
            contentHeight = height
            hasMeasuredHeight = true
        }
        .accessibilityIdentifier("paletteSheet")
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear {
            Haptics.shared.prepareForButton()
        }
    }

    private var grid: some View {
        let sideInset: CGFloat = 23
        let hGap: CGFloat = 12
        let vGap: CGFloat = 14
        let diameter = (screenWidth - 2 * sideInset - 2 * hGap) / 3
        let columns = Array(repeating: GridItem(.fixed(diameter), spacing: hGap), count: 3)
        return LazyVGrid(columns: columns, spacing: vGap) {
            ForEach(Self.displayOrder, id: \.self) { bubbleColor in
                swatch(for: bubbleColor, diameter: diameter)
            }
        }
        .padding(.horizontal, sideInset)
    }

    private func swatch(for bubbleColor: BubbleColor, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: store.color(for: bubbleColor)))
                .frame(width: diameter, height: diameter)

            ColorPickerAnchor(color: uiColorBinding(for: bubbleColor))
                .frame(width: diameter, height: diameter)
        }
        .accessibilityIdentifier("paletteSwatch\(bubbleColor.rawValue)")
    }

    private func uiColorBinding(for bubbleColor: BubbleColor) -> Binding<UIColor> {
        Binding(
            get: { store.color(for: bubbleColor) },
            set: { store.setColor($0, for: bubbleColor) }
        )
    }
}

/// Presents `UIColorPickerViewController` directly as a non-adaptive popover
/// anchored on its own view, in place of SwiftUI's `ColorPicker` (owner
/// feedback on spec 32). Two problems with the SwiftUI control drove this:
/// - It was overlaid nearly invisibly on our circle with a separate
///   `simultaneousGesture` added just to fire the haptic. That second
///   gesture recognizer competed with the control's own internal tap
///   recognizer for the same touch, so the first tap was consumed by ours
///   and only the second one actually reached the control and opened the
///   picker.
/// - `ColorPicker`'s picker presents adaptively, which becomes a full
///   sheet-style presentation on iPhone — presenting that over our own
///   already-open sheet visibly resized/jiggled it.
/// A single `UITapGestureRecognizer` here both fires the haptic and
/// presents the picker, so one tap always does both, and forcing
/// `adaptivePresentationStyle(for:) -> .none` keeps the picker a small
/// anchored popover instead of adapting to a sheet, so the presenting
/// sheet's own layout is never touched.
private struct ColorPickerAnchor: UIViewControllerRepresentable {
    @Binding var color: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> AnchorViewController {
        let anchor = AnchorViewController()
        anchor.onTap = { [weak anchor] in
            guard let anchor else { return }
            Haptics.shared.buttonTapped()
            let picker = UIColorPickerViewController()
            picker.selectedColor = context.coordinator.parent.color
            picker.supportsAlpha = false
            picker.delegate = context.coordinator
            picker.modalPresentationStyle = .popover
            picker.popoverPresentationController?.sourceView = anchor.view
            picker.popoverPresentationController?.sourceRect = anchor.view.bounds
            picker.popoverPresentationController?.delegate = context.coordinator
            anchor.present(picker, animated: true)
        }
        return anchor
    }

    func updateUIViewController(_ uiViewController: AnchorViewController, context: Context) {
        context.coordinator.parent = self
    }

    /// Transparent view controller that exists only to host the tap
    /// recognizer and act as the popover's presenter/anchor.
    final class AnchorViewController: UIViewController {
        var onTap: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        @objc private func handleTap() {
            onTap?()
        }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIPopoverPresentationControllerDelegate {
        var parent: ColorPickerAnchor

        init(_ parent: ColorPickerAnchor) {
            self.parent = parent
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            parent.color = color
        }

        /// Forces the popover to stay a popover on iPhone's compact width
        /// instead of adapting to a full sheet-style presentation — the fix
        /// for the presenting sheet jiggling (see type-level doc).
        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            .none
        }
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) { PaletteSheet() }
}
