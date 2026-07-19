import Foundation

/// Codex 的 Electron 辅助功能树会在当前窗口中嵌套超过 30 层。
/// 听写仍要求遍历完整和控件唯一，只是使用足以覆盖当前窗口的预算。
enum CodexDictationTraversalPolicy {
    static let nodeLimit = 8_000
    static let maximumDepth = 64

    static func accepts(
        traversalComplete: Bool,
        startControlCount: Int,
        stopControlCount: Int
    ) -> Bool {
        traversalComplete &&
            startControlCount <= 1 &&
            stopControlCount <= 1
    }
}
