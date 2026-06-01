// ViewControllerInspector.swift
// AppProbe
//
// ViewController 层级检查核心实现。

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "vc-inspector")

@MainActor
enum ViewControllerInspector {

    static func hierarchy(maxDepth: Int?, highlightClass: String?) -> VCHierarchyResponse {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        var sceneInfos: [VCSceneInfo] = []
        for scene in scenes {
            guard let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                  ?? scene.windows.first?.rootViewController else {
                continue
            }
            let title = scene.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Default"
            let node = buildNode(for: rootVC, depth: 0, maxDepth: maxDepth, highlightClass: highlightClass)
            sceneInfos.append(VCSceneInfo(sceneTitle: title, rootViewController: node))
        }

        let windowCount = scenes.reduce(0) { $0 + $1.windows.count }
        return VCHierarchyResponse(windowCount: windowCount, scenes: sceneInfos)
    }

    static func current() -> VCCurrentResponse? {
        guard let rootVC = keyWindowRootVC() else { return nil }

        var chain: [UIViewController] = []
        let topVC = findTopMost(from: rootVC, chain: &chain)

        let navInfo: VCNavigationInfo?
        if let nav = topVC.navigationController {
            navInfo = VCNavigationInfo(
                className: String(describing: type(of: nav)),
                stackDepth: nav.viewControllers.count,
                stackClasses: nav.viewControllers.map { String(describing: type(of: $0)) }
            )
        } else {
            navInfo = nil
        }

        let presentationChain = chain.map { String(describing: type(of: $0)) }
        let viewAddress: String? = topVC.isViewLoaded ? String(format: "%p", topVC.view) : nil

        return VCCurrentResponse(
            className: String(describing: type(of: topVC)),
            address: String(format: "%p", topVC),
            title: topVC.title,
            isViewLoaded: topVC.isViewLoaded,
            isVisible: topVC.isViewLoaded && topVC.view.window != nil,
            parentNavigation: navInfo,
            presentationChain: presentationChain,
            viewAddress: viewAddress
        )
    }

    // MARK: - Private

    private static func buildNode(for vc: UIViewController, depth: Int, maxDepth: Int?, highlightClass: String?) -> VCNodeInfo {
        let className = String(describing: type(of: vc))
        let address = String(format: "%p", vc)
        let isViewLoaded = vc.isViewLoaded
        let isVisible = isViewLoaded && vc.view.window != nil
        let highlighted = highlightClass.map { className == $0 }

        let atMaxDepth = maxDepth.map { depth >= $0 } ?? false

        var selectedIndex: Int? = nil
        var tabs: [VCNodeInfo]? = nil
        var navigationStack: [VCNodeInfo]? = nil
        var children: [VCNodeInfo]? = nil
        var presentedNode: VCNodeInfo? = nil

        if !atMaxDepth {
            if let tabVC = vc as? UITabBarController {
                selectedIndex = tabVC.selectedIndex
                tabs = tabVC.viewControllers?.map {
                    buildNode(for: $0, depth: depth + 1, maxDepth: maxDepth, highlightClass: highlightClass)
                }
            } else if let navVC = vc as? UINavigationController {
                navigationStack = navVC.viewControllers.map {
                    buildNode(for: $0, depth: depth + 1, maxDepth: maxDepth, highlightClass: highlightClass)
                }
            } else if !vc.children.isEmpty {
                children = vc.children.map {
                    buildNode(for: $0, depth: depth + 1, maxDepth: maxDepth, highlightClass: highlightClass)
                }
            }

            if let presented = vc.presentedViewController {
                presentedNode = buildNode(for: presented, depth: depth + 1, maxDepth: maxDepth, highlightClass: highlightClass)
            }
        }

        return VCNodeInfo(
            className: className, address: address, title: vc.title,
            isViewLoaded: isViewLoaded, isVisible: isVisible,
            selectedIndex: selectedIndex, tabs: tabs, navigationStack: navigationStack,
            presentedViewController: presentedNode, children: children, highlighted: highlighted
        )
    }

    private static func findTopMost(from vc: UIViewController, chain: inout [UIViewController]) -> UIViewController {
        chain.append(vc)
        var current = vc

        if let tabVC = current as? UITabBarController, let selected = tabVC.selectedViewController {
            current = selected
            chain.append(current)
        }
        if let navVC = current as? UINavigationController, let top = navVC.topViewController {
            current = top
            chain.append(current)
        }

        while let presented = current.presentedViewController {
            current = presented
            chain.append(current)
            if let tabVC = current as? UITabBarController, let selected = tabVC.selectedViewController {
                current = selected
                chain.append(current)
            }
            if let navVC = current as? UINavigationController, let top = navVC.topViewController {
                current = top
                chain.append(current)
            }
        }

        return current
    }

    private static func keyWindowRootVC() -> UIViewController? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow?.rootViewController
        } else {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        }
    }
}
