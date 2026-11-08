import UIKit

/// The home-screen icon follows the palette set (spec 66). Every set has an
/// icon of its own, a circle of one of its colors on another, made by
/// `scripts/make-app-icon.py`: the default set (`PaletteSet.default`) has
/// the primary icon, every other set the alternate icon `AppIcon-<set id>`.
/// An icon can't be drawn at run time, so colors edited by hand keep the icon
/// of the set they started from.
///
/// iOS confirms every change of icon with an alert of its own, so the icon
/// isn't switched while sets are being tried in the sheet, only once a
/// palette sheet closes, and when the app comes to the foreground — which
/// catches up on a change that never got there.
enum HomeScreenIcon {
    static func sync() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, let setId = PaletteStore.shared.selectedSetId else { return }
        let name = setId == PaletteSet.default.id ? nil : "AppIcon-\(setId)"
        guard app.alternateIconName != name else { return }
        app.setAlternateIconName(name) { error in
            if let error { print("HomeScreenIcon: \(name ?? "primary"): \(error.localizedDescription)") }
        }
    }
}
