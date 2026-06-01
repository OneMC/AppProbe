// ViewActionHelper.swift
// AppProbe
//
// 视图检查辅助类：ViewFinder 调用、主线程截图、高亮逻辑

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "view-helper")

/// 视图操作辅助类
enum ViewActionHelper {

    /// 在主线程同步执行闭包（防止从主线程调用时死锁）
    private static func onMainSync<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync { block() }
        }
    }

    /// 获取当前 Window 总数
    static func windowCount() -> Int {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .reduce(0) { $0 + $1.windows.count }
    }

    /// 在主线程查找视图并返回检查响应
    static func inspectView(
        tag: Int? = nil,
        className: String? = nil,
        address: String? = nil,
        includeSubviews: Bool = true,
        maxDepth: Int? = 15
    ) -> ActionResponse {
        var response: ActionResponse = .error(code: 500, message: "Internal error")

        onMainSync {
            // 按优先级查找：tag > class > address > 全局
            if let tag = tag {
                let result = ViewFinder.findByTag(tag)
                response = buildInspectResponse(result: result, tag: tag, className: nil,
                                                address: nil, includeSubviews: includeSubviews, maxDepth: maxDepth)
            } else if let className = className {
                let result = ViewFinder.findByClass(className)
                response = buildInspectResponse(result: result, tag: nil, className: className,
                                                address: nil, includeSubviews: includeSubviews, maxDepth: maxDepth)
            } else if let address = address {
                let result = ViewFinder.findByAddress(address)
                response = buildInspectResponse(result: result, tag: nil, className: nil,
                                                address: address, includeSubviews: includeSubviews, maxDepth: maxDepth)
            } else {
                // 无参数 → keyWindow 完整层级
                response = buildFullHierarchyResponse(maxDepth: maxDepth)
            }
        }

        return response
    }

    /// 在主线程执行高亮并截图
    static func highlightAndCapture(
        tag: Int?,
        address: String?,
        borderColorHex: String?,
        borderWidth: Double?,
        quality: Double?,
        scale: Double?,
        format: String?
    ) -> ActionResponse {
        var response: ActionResponse = .error(code: 500, message: "Internal error")

        onMainSync {
            let result: ViewFinderResult
            if let tag = tag {
                result = ViewFinder.findByTag(tag)
            } else if let address = address {
                result = ViewFinder.findByAddress(address)
            } else {
                response = .error(code: 400, message: "Missing 'tag' or 'address' query parameter")
                return
            }

            switch result {
            case .found(let view, _):
                let color: UIColor
                if let hex = borderColorHex, let parsed = UIColor(hexString: hex) {
                    color = parsed
                } else {
                    color = .red
                }
                let width = borderWidth.map { CGFloat($0) } ?? 2

                // 临时添加边框
                let originalBorderColor = view.layer.borderColor
                let originalBorderWidth = view.layer.borderWidth
                view.layer.borderColor = color.cgColor
                view.layer.borderWidth = width

                let finalQuality = quality ?? 0.75
                let finalScale = max(0.1, min(3.0, scale ?? 1.0))
                let finalFormat = (format == "png") ? "png" : "jpeg"

                let screenshotResult = view.inspectorCompressedScreenshot(
                    quality: finalQuality, scale: finalScale, format: finalFormat
                )

                // 恢复原始边框
                view.layer.borderColor = originalBorderColor
                view.layer.borderWidth = originalBorderWidth

                guard let captured = screenshotResult else {
                    response = .error(code: 500, message: "Failed to capture screenshot")
                    return
                }

                let contentType = finalFormat == "png" ? "image/png" : "image/jpeg"
                var headers: [String: String] = [
                    "X-Image-Width": "\(Int(captured.outputSize.width))",
                    "X-Image-Height": "\(Int(captured.outputSize.height))",
                    "X-Original-Width": "\(Int(view.bounds.size.width))",
                    "X-Original-Height": "\(Int(view.bounds.size.height))",
                    "X-Image-Format": finalFormat,
                    "X-Image-Scale": "\(finalScale)",
                ]
                if finalFormat != "png" {
                    headers["X-Image-Quality"] = "\(finalQuality)"
                }
                response = .raw(data: captured.data, contentType: contentType, headers: headers)

            case .notFound:
                response = .error(code: 404, message: "View not found")
            }
        }

        return response
    }

    /// 在主线程截图
    static func captureScreenshot(
        tag: Int?,
        className: String?,
        address: String?,
        quality: Double?,
        scale: Double?,
        format: String?
    ) -> ActionResponse {
        var response: ActionResponse = .error(code: 500, message: "Internal error")

        onMainSync {
            let targetView: UIView?

            if let tag = tag {
                if case .found(let view, _) = ViewFinder.findByTag(tag) {
                    targetView = view
                } else { targetView = nil }
            } else if let className = className {
                if case .found(let view, _) = ViewFinder.findByClass(className) {
                    targetView = view
                } else { targetView = nil }
            } else if let address = address {
                if case .found(let view, _) = ViewFinder.findByAddress(address) {
                    targetView = view
                } else { targetView = nil }
            } else {
                targetView = ViewFinder.keyWindow()
            }

            guard let view = targetView else {
                response = .error(code: 404, message: "View not found")
                return
            }

            let finalQuality = quality ?? 0.75
            let finalScale = max(0.1, min(3.0, scale ?? 1.0))
            let finalFormat = (format == "png") ? "png" : "jpeg"

            guard let result = view.inspectorCompressedScreenshot(
                quality: finalQuality, scale: finalScale, format: finalFormat
            ) else {
                response = .error(code: 500, message: "Failed to capture screenshot")
                return
            }

            let contentType = finalFormat == "png" ? "image/png" : "image/jpeg"
            var headers: [String: String] = [
                "X-Image-Width": "\(Int(result.outputSize.width))",
                "X-Image-Height": "\(Int(result.outputSize.height))",
                "X-Original-Width": "\(Int(view.bounds.size.width))",
                "X-Original-Height": "\(Int(view.bounds.size.height))",
                "X-Image-Format": finalFormat,
                "X-Image-Scale": "\(finalScale)",
            ]
            if finalFormat != "png" {
                headers["X-Image-Quality"] = "\(finalQuality)"
            }
            response = .raw(data: result.data, contentType: contentType, headers: headers)
        }

        return response
    }

    // MARK: - Private

    private static func buildInspectResponse(
        result: ViewFinderResult,
        tag: Int?,
        className: String?,
        address: String?,
        includeSubviews: Bool,
        maxDepth: Int? = 15
    ) -> ActionResponse {
        switch result {
        case .found(let view, let scannedCount):
            let viewInfo = view.inspectorViewInfo()
            var hierarchyResult: InspectorHierarchyResult?
            if includeSubviews {
                let tree = view.inspectorHierarchyNode(maxDepth: maxDepth)
                hierarchyResult = InspectorHierarchyResult(
                    depth: view.inspectorDepth(),
                    subviewCount: view.inspectorSubviewCount(),
                    tree: tree
                )
            }
            let searchInfo = InspectorSearchInfo(
                tag: tag, className: className, address: address,
                windowCount: windowCount(), totalViewsScanned: scannedCount
            )
            let resp = InspectorResponse(
                found: true, target: viewInfo, hierarchy: hierarchyResult,
                error: nil, searched: searchInfo
            )
            return .json(resp)

        case .notFound(let scannedCount):
            let searchInfo = InspectorSearchInfo(
                tag: tag, className: className, address: address,
                windowCount: windowCount(), totalViewsScanned: scannedCount
            )
            let errorMsg: String
            if let tag = tag { errorMsg = "View with tag \(tag) not found" }
            else if let className = className { errorMsg = "View of class '\(className)' not found" }
            else if let address = address { errorMsg = "View at address '\(address)' not found" }
            else { errorMsg = "View not found" }

            let resp = InspectorResponse(
                found: false, target: nil, hierarchy: nil,
                error: errorMsg, searched: searchInfo
            )
            return .jsonWithStatus(resp, statusCode: 404)
        }
    }

    private static func buildFullHierarchyResponse(maxDepth: Int? = 15) -> ActionResponse {
        guard let window = ViewFinder.keyWindow() else {
            let searchInfo = InspectorSearchInfo(
                tag: nil, className: nil, address: nil,
                windowCount: windowCount(), totalViewsScanned: 0
            )
            let resp = InspectorResponse(
                found: false, target: nil, hierarchy: nil,
                error: "No key window found", searched: searchInfo
            )
            return .jsonWithStatus(resp, statusCode: 404)
        }

        let tree = window.inspectorHierarchyNode(maxDepth: maxDepth)
        let scannedCount = window.inspectorSubviewCount() + 1
        let hierarchyResult = InspectorHierarchyResult(
            depth: window.inspectorDepth(),
            subviewCount: window.inspectorSubviewCount(),
            tree: tree
        )
        let searchInfo = InspectorSearchInfo(
            tag: nil, className: nil, address: nil,
            windowCount: windowCount(), totalViewsScanned: scannedCount
        )
        let resp = InspectorResponse(
            found: true, target: nil, hierarchy: hierarchyResult,
            error: nil, searched: searchInfo
        )
        return .json(resp)
    }
}

// MARK: - UIColor Hex Parsing (internal)

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")

        var rgba: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgba) else { return nil }

        let length = hex.count
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

        switch length {
        case 6:
            r = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgba & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgba & 0x000000FF) / 255.0
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
