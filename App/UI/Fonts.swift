import SwiftUI
import CoreText

/// Registers the bundled Pretendard-SemiBold font with CoreText so
/// `Font.custom("Pretendard-SemiBold", ...)` resolves to it. XcodeGen
/// generates `Info.plist` (`GENERATE_INFOPLIST_FILE: YES`), so there's no
/// static `UIAppFonts` array to add the font to; runtime registration is a
/// few lines and doesn't touch the build configuration. If the font file is
/// missing or fails to register, `Font.custom` silently falls back to the
/// system font instead of crashing.
enum Fonts {
    /// PostScript name of the bundled font, as reported by the font itself.
    static let pretendardSemiBoldName = "Pretendard-SemiBold"

    /// Registers the font exactly once, the first time this is touched.
    static let register: Void = {
        guard let url = Bundle.main.url(forResource: "Pretendard-SemiBold", withExtension: "otf") else {
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }()
}

/// Which font the whole app is set in (spec 55, a test). Pretendard stays
/// bundled and registered; the launch argument `-pretendard` switches back
/// to it for a side-by-side comparison without rebuilding. To switch for
/// good, change the default branch of `current` (and drop the argument).
enum AppFont {
    case sfRounded
    case pretendard

    static let current: AppFont = CommandLine.arguments.contains("-pretendard") ? .pretendard : .sfRounded
}

extension Font {
    /// Semibold in the app's current font (see `AppFont`); every text in the
    /// app goes through this.
    static func appSemiBold(_ size: CGFloat) -> Font {
        switch AppFont.current {
        case .sfRounded: Font.system(size: size, weight: .semibold, design: .rounded)
        case .pretendard: pretendardSemiBold(size)
        }
    }

    /// Pretendard-SemiBold at the given size; falls back to the system font
    /// automatically if the custom font never registered.
    static func pretendardSemiBold(_ size: CGFloat) -> Font {
        Fonts.register
        return Font.custom(Fonts.pretendardSemiBoldName, size: size)
    }
}
