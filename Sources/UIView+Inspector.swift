// UIView+Inspector.swift
// AppProbe
//
// UIView 及相关 UIKit 组件的运行时信息提取扩展。
// 提供以下能力：
// - UIColor → Hex 字符串转换
// - CALayer 层属性提取（圆角、阴影、边框）
// - NSLayoutConstraint 约束信息提取
// - UILabel / UIImageView / UIButton 特有属性提取
// - UIView 完整属性快照、层级树构建、压缩截图

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "view")

// MARK: - UIColor Extension

/// UIColor → Hex 字符串转换，支持 6 位（RGB）和 8 位（RGBA）输出
extension UIColor {
    func inspectorHexString() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        let a = Int(alpha * 255)

        if alpha < 1.0 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
}

// MARK: - CALayer Extension

/// CALayer 层属性提取：圆角、边框、阴影等视觉属性
extension CALayer {
    /// 提取 Layer 的视觉属性信息
    func inspectorLayerInfo() -> InspectorLayerInfo {
        return InspectorLayerInfo(
            cornerRadius: Double(self.cornerRadius),
            borderWidth: Double(self.borderWidth),
            borderColor: self.borderColor.map { UIColor(cgColor: $0).inspectorHexString() },
            shadowColor: self.shadowColor.map { UIColor(cgColor: $0).inspectorHexString() },
            shadowOffset: InspectorSize(from: self.shadowOffset),
            shadowRadius: Double(self.shadowRadius),
            shadowOpacity: Double(self.shadowOpacity)
        )
    }
}

// MARK: - NSLayoutConstraint Extension

/// 约束信息提取：将 NSLayoutConstraint 转换为可序列化的描述
extension NSLayoutConstraint {
    /// 提取约束的关键属性（firstItem、attribute、relation、constant 等）
    func inspectorInfo() -> InspectorConstraintInfo {
        return InspectorConstraintInfo(
            firstItem: String(describing: type(of: self.firstItem)),
            firstAttribute: attributeString(self.firstAttribute),
            relation: relationString(self.relation),
            secondItem: self.secondItem.map { String(describing: type(of: $0)) },
            secondAttribute: self.secondAttribute != .notAnAttribute ? attributeString(self.secondAttribute) : nil,
            multiplier: Double(self.multiplier),
            constant: Double(self.constant)
        )
    }

    /// 将 NSLayoutConstraint.Attribute 转换为可读字符串
    private func attributeString(_ attribute: NSLayoutConstraint.Attribute) -> String {
        switch attribute {
        case .left: return "left"
        case .right: return "right"
        case .top: return "top"
        case .bottom: return "bottom"
        case .leading: return "leading"
        case .trailing: return "trailing"
        case .width: return "width"
        case .height: return "height"
        case .centerX: return "centerX"
        case .centerY: return "centerY"
        case .lastBaseline: return "lastBaseline"
        case .firstBaseline: return "firstBaseline"
        case .leftMargin: return "leftMargin"
        case .rightMargin: return "rightMargin"
        case .topMargin: return "topMargin"
        case .bottomMargin: return "bottomMargin"
        case .leadingMargin: return "leadingMargin"
        case .trailingMargin: return "trailingMargin"
        case .centerXWithinMargins: return "centerXWithinMargins"
        case .centerYWithinMargins: return "centerYWithinMargins"
        case .notAnAttribute: return "notAnAttribute"
        @unknown default: return "unknown"
        }
    }

    /// 将 NSLayoutConstraint.Relation 转换为可读字符串（==、<=、>=）
    private func relationString(_ relation: NSLayoutConstraint.Relation) -> String {
        switch relation {
        case .lessThanOrEqual: return "<="
        case .equal: return "=="
        case .greaterThanOrEqual: return ">="
        @unknown default: return "unknown"
        }
    }
}

// MARK: - UILabel Extension

/// UILabel 特有属性提取：文本内容、字体、颜色、对齐方式
extension UILabel {
    /// 提取 UILabel 的文本属性
    func inspectorLabelInfo() -> InspectorLabelInfo {
        let alignmentString: String
        switch self.textAlignment {
        case .left: alignmentString = "left"
        case .center: alignmentString = "center"
        case .right: alignmentString = "right"
        case .justified: alignmentString = "justified"
        case .natural: alignmentString = "natural"
        @unknown default: alignmentString = "unknown"
        }

        let fontName = self.font.fontName
        let fontSize = Double(self.font.pointSize)

        return InspectorLabelInfo(
            text: self.text ?? "",
            font: InspectorFontInfo(name: fontName, size: fontSize),
            textColor: self.textColor.inspectorHexString(),
            textAlignment: alignmentString
        )
    }
}

// MARK: - UIImageView Extension

/// UIImageView 特有属性提取：contentMode
extension UIImageView {
    /// 提取 UIImageView 的显示模式
    func inspectorImageViewInfo() -> InspectorImageViewInfo {
        let contentModeString: String
        switch self.contentMode {
        case .scaleToFill: contentModeString = "scaleToFill"
        case .scaleAspectFit: contentModeString = "scaleAspectFit"
        case .scaleAspectFill: contentModeString = "scaleAspectFill"
        case .redraw: contentModeString = "redraw"
        case .center: contentModeString = "center"
        case .top: contentModeString = "top"
        case .bottom: contentModeString = "bottom"
        case .left: contentModeString = "left"
        case .right: contentModeString = "right"
        case .topLeft: contentModeString = "topLeft"
        case .topRight: contentModeString = "topRight"
        case .bottomLeft: contentModeString = "bottomLeft"
        case .bottomRight: contentModeString = "bottomRight"
        @unknown default: contentModeString = "unknown"
        }

        return InspectorImageViewInfo(contentMode: contentModeString)
    }
}

// MARK: - UIButton Extension

/// UIButton 特有属性提取：标题文本
extension UIButton {
    /// 提取 UIButton 的普通状态标题
    func inspectorButtonInfo() -> InspectorButtonInfo {
        let title = self.title(for: .normal) ?? ""
        return InspectorButtonInfo(title: title)
    }
}

// MARK: - UIView Extension

/// UIView 核心扩展：属性提取、截图、层级树构建
extension UIView {
    /// 提取视图的完整属性快照（frame、bounds、alpha、背景色、约束等）
    func inspectorViewInfo() -> InspectorViewInfo {
        logger.debug("[viewInfo] 提取属性: \(String(describing: type(of: self))), address=\(String(format: "%p", self))")
        let backgroundColorHex = self.backgroundColor?.inspectorHexString()
        let tintColorHex = self.tintColor?.inspectorHexString()

        let constraintInfos = self.constraints.map { $0.inspectorInfo() }

        return InspectorViewInfo(
            address: String(format: "%p", self),
            className: String(describing: type(of: self)),
            tag: self.tag,
            frame: InspectorRect(from: self.frame),
            bounds: InspectorRect(from: self.bounds),
            center: InspectorPoint(from: self.center),
            alpha: Double(self.alpha),
            isHidden: self.isHidden,
            isUserInteractionEnabled: self.isUserInteractionEnabled,
            backgroundColor: backgroundColorHex,
            tintColor: tintColorHex,
            layerInfo: self.layer.inspectorLayerInfo(),
            constraints: constraintInfos
        )
    }

    /// 递归构建视图层级树节点（包含子视图）
    /// - Parameter maxDepth: 最大递归深度，nil 表示不限制
    func inspectorHierarchyNode(maxDepth: Int? = nil, currentDepth: Int = 0) -> InspectorHierarchyNode {
        let subviewNodes: [InspectorHierarchyNode]
        if let max = maxDepth, currentDepth >= max {
            subviewNodes = []
        } else {
            subviewNodes = self.subviews.map { $0.inspectorHierarchyNode(maxDepth: maxDepth, currentDepth: currentDepth + 1) }
        }

        var labelInfo: InspectorLabelInfo?
        var imageViewInfo: InspectorImageViewInfo?
        var buttonInfo: InspectorButtonInfo?

        if let label = self as? UILabel {
            labelInfo = label.inspectorLabelInfo()
        } else if let imageView = self as? UIImageView {
            imageViewInfo = imageView.inspectorImageViewInfo()
        } else if let button = self as? UIButton {
            buttonInfo = button.inspectorButtonInfo()
        }

        return InspectorHierarchyNode(
            className: String(describing: type(of: self)),
            address: String(format: "%p", self),
            tag: self.tag,
            frame: InspectorRect(from: self.frame),
            alpha: Double(self.alpha),
            isHidden: self.isHidden,
            subviews: subviewNodes,
            labelInfo: labelInfo,
            imageViewInfo: imageViewInfo,
            buttonInfo: buttonInfo
        )
    }

    /// 递归统计所有子视图总数
    func inspectorSubviewCount() -> Int {
        var count = self.subviews.count
        for subview in self.subviews {
            count += subview.inspectorSubviewCount()
        }
        return count
    }

    /// 计算视图层级的最大深度
    func inspectorDepth() -> Int {
        if self.subviews.isEmpty {
            return 1
        }
        var maxDepth = 0
        for subview in self.subviews {
            maxDepth = max(maxDepth, subview.inspectorDepth())
        }
        return maxDepth + 1
    }

    /// 截取当前视图内容，支持缩放和 JPEG 压缩
    ///
    /// - Parameters:
    ///   - quality: JPEG 压缩质量 (0.0-1.0)，仅 format 为 jpeg 时有效
    ///   - scale: 渲染缩放比例（如 1.0 = 原始大小，0.5 = 缩小一半）
    ///   - format: 输出格式 "jpeg" 或 "png"
    /// - Returns: (imageData, outputSize) 元组，失败返回 nil
    func inspectorCompressedScreenshot(
        quality: Double,
        scale: Double,
        format: String
    ) -> (data: Data, outputSize: CGSize)? {
        let scaledSize = CGSize(
            width: self.bounds.width * CGFloat(scale),
            height: self.bounds.height * CGFloat(scale)
        )

        guard scaledSize.width > 0 && scaledSize.height > 0 else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            self.layer.render(in: context.cgContext)
        }

        let data: Data?
        if format == "png" {
            data = image.pngData()
        } else {
            data = image.jpegData(compressionQuality: CGFloat(quality))
        }

        guard let imageData = data else {
            return nil
        }

        return (data: imageData, outputSize: scaledSize)
    }
}
