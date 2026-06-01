// AppProbeModels.swift
// AppProbe
//
// 视图检查 API 的数据模型定义。
// 包含几何信息（Rect/Point/Size）、视图属性（ViewInfo）、
// 层级树（HierarchyNode）、截图信息、搜索结果、高亮请求/响应等。

import UIKit

// MARK: - Geometry Helpers

/// 矩形区域（对应 CGRect）
struct InspectorRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
}

/// 点坐标（对应 CGPoint）
struct InspectorPoint: Codable {
    let x: Double
    let y: Double

    init(from point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }
}

/// 尺寸（对应 CGSize）
struct InspectorSize: Codable {
    let width: Double
    let height: Double

    init(from size: CGSize) {
        self.width = Double(size.width)
        self.height = Double(size.height)
    }
}

// MARK: - Layer Info

/// CALayer 视觉属性（圆角、边框、阴影）
struct InspectorLayerInfo: Codable {
    let cornerRadius: Double
    let borderWidth: Double
    let borderColor: String?
    let shadowColor: String?
    let shadowOffset: InspectorSize
    let shadowRadius: Double
    let shadowOpacity: Double
}

// MARK: - Constraint Info

/// Auto Layout 约束描述
struct InspectorConstraintInfo: Codable {
    let firstItem: String
    let firstAttribute: String
    let relation: String
    let secondItem: String?
    let secondAttribute: String?
    let multiplier: Double
    let constant: Double
}

// MARK: - View Info

/// UIView 完整属性快照（inspect API 的核心返回数据）
struct InspectorViewInfo: Codable {
    /// 内存地址（如 0x7f8b1c005a00）
    let address: String
    /// 类名（如 UILabel、UIButton）
    let className: String
    let tag: Int
    let frame: InspectorRect
    let bounds: InspectorRect
    let center: InspectorPoint
    let alpha: Double
    let isHidden: Bool
    let isUserInteractionEnabled: Bool
    let backgroundColor: String?
    let tintColor: String?
    let layerInfo: InspectorLayerInfo
    let constraints: [InspectorConstraintInfo]
}

// MARK: - Hierarchy Node

/// UILabel 文本属性
struct InspectorLabelInfo: Codable {
    let text: String
    let font: InspectorFontInfo
    let textColor: String
    let textAlignment: String
}

/// 字体属性
struct InspectorFontInfo: Codable {
    let name: String
    let size: Double
}

/// UIImageView 显示模式
struct InspectorImageViewInfo: Codable {
    let contentMode: String
}

/// UIButton 标题信息
struct InspectorButtonInfo: Codable {
    let title: String
}

/// 视图层级树节点（递归结构，包含子视图）
struct InspectorHierarchyNode: Codable {
    let className: String
    let address: String
    let tag: Int
    let frame: InspectorRect
    let alpha: Double
    let isHidden: Bool
    let subviews: [InspectorHierarchyNode]
    let labelInfo: InspectorLabelInfo?
    let imageViewInfo: InspectorImageViewInfo?
    let buttonInfo: InspectorButtonInfo?
}

// MARK: - Hierarchy Result

/// 层级分析结果（深度、子视图总数、层级树）
struct InspectorHierarchyResult: Codable {
    let depth: Int
    let subviewCount: Int
    let tree: InspectorHierarchyNode
}

// MARK: - Search Info

/// 搜索过程信息（搜索条件、扫描的窗口和视图数量）
struct InspectorSearchInfo: Codable {
    let tag: Int?
    let className: String?
    let address: String?
    let windowCount: Int
    let totalViewsScanned: Int
}

// MARK: - Main Response

/// inspect API 的主响应体
struct InspectorResponse: Codable {
    let found: Bool
    let target: InspectorViewInfo?
    let hierarchy: InspectorHierarchyResult?
    let error: String?
    let searched: InspectorSearchInfo?
}

// MARK: - Status

/// status API 响应体
struct StatusResponse: Codable {
    let status: String
    let serverVersion: String
    let appName: String
    let device: String
    let windowCount: Int
}

