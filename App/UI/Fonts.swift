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

extension Font {
    /// Pretendard-SemiBold at the given size; falls back to the system font
    /// automatically if the custom font never registered.
    static func pretendardSemiBold(_ size: CGFloat) -> Font {
        Fonts.register
        return Font.custom(Fonts.pretendardSemiBoldName, size: size)
    }
}
