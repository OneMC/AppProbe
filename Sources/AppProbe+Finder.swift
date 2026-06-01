// AppProbe+Finder.swift
// AppProbe
//
// 视图搜索引擎。负责在 UIView 层级树中查找目标视图。
// 支持三种搜索方式：tag 精确匹配、类名匹配（首个可见）、内存地址匹配。
// 搜索从所有 UIWindowScene 的 Window 开始，采用深度优先遍历。

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "finder")

/// 视图查找结果
enum ViewFinderResult {
    /// 找到目标视图，附带扫描的视图总数
    case found(UIView, scannedCount: Int)
    /// 未找到，附带扫描的视图总数
    case notFound(scannedCount: Int)
}

/// 视图搜索引擎
///
/// 从所有活跃的 UIWindowScene 中递归搜索视图，采用深度优先遍历策略。
/// 搜索过程统计扫描的视图数量，用于诊断和调试。
enum ViewFinder {

    /// 获取所有活跃 UIWindowScene 中的 Window
    private static func allWindows() -> [UIWindow] {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    /// 深度优先递归搜索视图
    ///
    /// - Parameters:
    ///   - view: 当前搜索的视图节点
    ///   - predicate: 匹配条件
    ///   - scannedCount: 已扫描视图计数器（inout）
    /// - Returns: 匹配的视图，未找到返回 nil
    private static func search(
        in view: UIView,
        predicate: (UIView) -> Bool,
        scannedCount: inout Int
    ) -> UIView? {
        scannedCount += 1

        if predicate(view) {
            return view
        }

        for subview in view.subviews {
            if let found = search(in: subview, predicate: predicate, scannedCount: &scannedCount) {
                return found
            }
        }

        return nil
    }

    /// 通过 tag 精确匹配查找视图
    ///
    /// 搜索所有 Window 中 tag 等于指定值的视图，返回第一个匹配结果。
    static func findByTag(_ tag: Int) -> ViewFinderResult {
        let windows = allWindows()
        var scannedCount = 0
        logger.debug("[findByTag] 开始搜索 tag=\(tag), 窗口数: \(windows.count)")

        for window in windows {
            if let found = search(in: window, predicate: { $0.tag == tag }, scannedCount: &scannedCount) {
                logger.info("[findByTag] 找到 tag=\(tag): \(String(describing: type(of: found))), 扫描 \(scannedCount) 个视图")
                return .found(found, scannedCount: scannedCount)
            }
        }

        logger.info("[findByTag] 未找到 tag=\(tag), 扫描 \(scannedCount) 个视图")
        return .notFound(scannedCount: scannedCount)
    }

    /// 通过类名查找视图（返回第一个可见匹配）
    ///
    /// 匹配条件：类名相同、isHidden 为 false、alpha 大于 0。
    static func findByClass(_ className: String) -> ViewFinderResult {
        let windows = allWindows()
        var scannedCount = 0
        logger.debug("[findByClass] 开始搜索 class=\(className), 窗口数: \(windows.count)")

        for window in windows {
            if let found = search(
                in: window,
                predicate: {
                    String(describing: type(of: $0)) == className
                        && !$0.isHidden
                        && $0.alpha > 0
                },
                scannedCount: &scannedCount
            ) {
                logger.info("[findByClass] 找到 class=\(className), 扫描 \(scannedCount) 个视图")
                return .found(found, scannedCount: scannedCount)
            }
        }

        logger.info("[findByClass] 未找到 class=\(className), 扫描 \(scannedCount) 个视图")
        return .notFound(scannedCount: scannedCount)
    }

    /// 通过内存地址查找视图
    ///
    /// 地址格式为 `0x...` 的十六进制指针字符串。
    static func findByAddress(_ address: String) -> ViewFinderResult {
        let windows = allWindows()
        var scannedCount = 0
        logger.debug("[findByAddress] 开始搜索 address=\(address), 窗口数: \(windows.count)")

        for window in windows {
            if let found = search(
                in: window,
                predicate: { String(format: "%p", $0) == address },
                scannedCount: &scannedCount
            ) {
                logger.info("[findByAddress] 找到 address=\(address): \(String(describing: type(of: found))), 扫描 \(scannedCount) 个视图")
                return .found(found, scannedCount: scannedCount)
            }
        }

        logger.info("[findByAddress] 未找到 address=\(address), 扫描 \(scannedCount) 个视图")
        return .notFound(scannedCount: scannedCount)
    }

    /// 获取当前 keyWindow（兼容 iOS 13+）
    ///
    /// - iOS 15+: 使用 UIWindowScene.keyWindow 属性
    /// - iOS 13-14: 遍历所有 WindowScene 的 windows，查找 isKeyWindow
    static func keyWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow
        } else {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })
        }
    }
}
