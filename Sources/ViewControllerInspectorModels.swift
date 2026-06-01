// ViewControllerInspectorModels.swift
// AppProbe
//
// ViewController 层级检查 API 的数据模型定义。

import Foundation

// MARK: - VC Hierarchy Response

struct VCHierarchyResponse: Codable {
    let windowCount: Int
    let scenes: [VCSceneInfo]
}

struct VCSceneInfo: Codable {
    let sceneTitle: String?
    let rootViewController: VCNodeInfo?
}

// MARK: - VC Node Info

final class VCNodeInfo: Codable {
    let className: String
    let address: String
    let title: String?
    let isViewLoaded: Bool
    let isVisible: Bool
    let selectedIndex: Int?
    let tabs: [VCNodeInfo]?
    let navigationStack: [VCNodeInfo]?
    let presentedViewController: VCNodeInfo?
    let children: [VCNodeInfo]?
    let highlighted: Bool?

    init(
        className: String,
        address: String,
        title: String?,
        isViewLoaded: Bool,
        isVisible: Bool,
        selectedIndex: Int? = nil,
        tabs: [VCNodeInfo]? = nil,
        navigationStack: [VCNodeInfo]? = nil,
        presentedViewController: VCNodeInfo? = nil,
        children: [VCNodeInfo]? = nil,
        highlighted: Bool? = nil
    ) {
        self.className = className
        self.address = address
        self.title = title
        self.isViewLoaded = isViewLoaded
        self.isVisible = isVisible
        self.selectedIndex = selectedIndex
        self.tabs = tabs
        self.navigationStack = navigationStack
        self.presentedViewController = presentedViewController
        self.children = children
        self.highlighted = highlighted
    }
}

// MARK: - Current VC Response

struct VCCurrentResponse: Codable {
    let className: String
    let address: String
    let title: String?
    let isViewLoaded: Bool
    let isVisible: Bool
    let parentNavigation: VCNavigationInfo?
    let presentationChain: [String]
    let viewAddress: String?
}

struct VCNavigationInfo: Codable {
    let className: String
    let stackDepth: Int
    let stackClasses: [String]
}
