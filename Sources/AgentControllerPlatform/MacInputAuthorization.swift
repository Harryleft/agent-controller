@preconcurrency import ApplicationServices
import CoreGraphics

/// macOS 事件投递权限与辅助功能权限的最小封装。
///
/// 普通快捷键只需要事件投递权限。可靠的 LT 听写还需要辅助功能
/// 权限，以便精确发现 Codex 控件并确认状态，二者不能互相替代。
public enum MacInputAuthorization {
    /// 当前进程是否可以投递合成输入事件。
    public static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// 请求系统显示“允许投递输入事件”的授权提示。
    @discardableResult
    public static func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    /// 当前进程是否已获辅助功能信任。
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能授权提示。
    @discardableResult
    public static func promptForAccessibilityTrust() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
    }
}
