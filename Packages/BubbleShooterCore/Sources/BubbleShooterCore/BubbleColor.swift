import Foundation

/// Bubble color index, matching the original's `myIdx` (0..5) and
/// `bubbleImgNameArr = ["bubble_blue", "bubble_red", "bubble_green",
/// "bubble_yellow", "bubble_purple", "bubble_lightblue"]`.
public enum BubbleColor: Int, CaseIterable, Codable, Hashable {
    case blue = 0, red, green, yellow, purple, lightblue
}
