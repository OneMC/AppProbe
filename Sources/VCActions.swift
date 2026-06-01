// VCActions.swift
// AppProbe
//
// ViewController 层级检查 Actions：Hierarchy、Current

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "vc-actions")

// MARK: - VCHierarchyAction

/// GET /vc/hierarchy — 完整 VC 层级树
final class VCHierarchyAction: AIAction {
    let module = "vc"
    let name = "hierarchy"
    let httpMethod = "GET"
    let summary = "获取完整 ViewController 层级树，识别 Nav/Tab/容器结构"
    let parameters = [
        APIParameterDescriptor(name: "depth", type: "Int", required: false, description: "限制递归深度（默认不限）"),
        APIParameterDescriptor(name: "class", type: "String", required: false, description: "高亮/标记指定类名的 VC"),
    ]
    let example = APIExample(
        requestURL: "/vc/hierarchy",
        responseBody: #"{"windowCount":1,"scenes":[{"sceneTitle":"Default","rootViewController":{"className":"UITabBarController","address":"0x100800000","title":null,"isViewLoaded":true,"isVisible":true,"selectedIndex":0,"tabs":[],"navigationStack":null,"presentedViewController":null,"children":null,"highlighted":null}}]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        let maxDepth = params["depth"].flatMap { Int($0) }
        let highlightClass = params["class"]

        var response: ActionResponse = .error(code: 500, message: "Internal error")
        let block = {
            MainActor.assumeIsolated {
                let result = ViewControllerInspector.hierarchy(maxDepth: maxDepth, highlightClass: highlightClass)
                response = .json(result)
            }
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync { block() }
        }
        return response
    }
}

// MARK: - VCCurrentAction

/// GET /vc/current — 当前最顶层可见 VC
final class VCCurrentAction: AIAction {
    let module = "vc"
    let name = "current"
    let httpMethod = "GET"
    let summary = "获取当前最顶层可见 ViewController 的详细信息，含导航栈和 present 链"
    let parameters: [APIParameterDescriptor] = []
    let example = APIExample(
        requestURL: "/vc/current",
        responseBody: #"{"className":"HomeViewController","address":"0x100900000","title":"Home","isViewLoaded":true,"isVisible":true,"parentNavigation":{"className":"UINavigationController","stackDepth":1,"stackClasses":["HomeViewController"]},"presentationChain":["UITabBarController","UINavigationController","HomeViewController"],"viewAddress":"0x100900100"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        var response: ActionResponse = .error(code: 404, message: "No visible ViewController found")
        let block = {
            MainActor.assumeIsolated {
                guard let result = ViewControllerInspector.current() else { return }
                response = .json(result)
            }
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync { block() }
        }
        return response
    }
}
