// APIRegistry.swift
// AppProbe
//
// API 中央注册表。持有所有已注册 AIAction 实例。
// 线程安全：所有读写操作通过 NSLock 保护。

import Foundation
import os

private let logger = Logger(subsystem: "com.appprobe", category: "registry")

// MARK: - APIRegistry

/// API 中央注册表
///
/// 所有 API（内置 + 业务）通过 `register(_:)` 注册，通过 `unregister(module:name:)` 注销。
/// 元数据直接从 AIAction 实例读取，无需额外 descriptor。
final class APIRegistry {
    static let shared = APIRegistry()

    /// 所有已注册的 action，key = path
    private var actions: [String: AIAction] = [:]

    /// 所有已注册的 module 描述，key = module name
    private var modules: [String: ModuleDescriptor] = [:]

    private let lock = NSLock()

    private init() {}

    // MARK: - Registration

    /// 注册 action（内置和业务统一入口）
    func register(_ action: AIAction) {
        let path = action.path
        lock.lock()
        actions[path] = action
        lock.unlock()
        logger.info("[registry] 注册 action: \(action.httpMethod) \(path)")
    }

    /// 注销 action
    func unregister(module: String, name: String) {
        let path = name.isEmpty ? "/\(module)" : "/\(module)/\(name)"
        lock.lock()
        actions.removeValue(forKey: path)
        lock.unlock()
        logger.info("[registry] 注销 action: \(path)")
    }

    /// 注册 module 描述
    func registerModule(name: String, description: String) {
        let descriptor = ModuleDescriptor(name: name, description: description)
        lock.lock()
        modules[name] = descriptor
        lock.unlock()
        logger.debug("[registry] 注册 module: \(name)")
    }

    // MARK: - Query

    /// 根据路径获取 action
    func action(forPath path: String) -> AIAction? {
        lock.lock()
        let result = actions[path]
        lock.unlock()
        return result
    }

    /// 获取所有 action（按路径排序）
    func allActions() -> [AIAction] {
        lock.lock()
        let result = Array(actions.values).sorted { $0.path < $1.path }
        lock.unlock()
        return result
    }

    /// 获取指定 module 下的所有 action（按路径排序）
    func actions(forModule module: String) -> [AIAction] {
        lock.lock()
        let result = actions.values
            .filter { $0.module == module }
            .sorted { $0.path < $1.path }
        lock.unlock()
        return result
    }

    /// 获取所有 module 描述（按名称排序）
    func allModules() -> [ModuleDescriptor] {
        lock.lock()
        let result = Array(modules.values).sorted { $0.name < $1.name }
        lock.unlock()
        return result
    }

    /// 获取指定 module 的描述
    func module(forName name: String) -> ModuleDescriptor? {
        lock.lock()
        let result = modules[name]
        lock.unlock()
        return result
    }

    /// 清空所有注册（仅用于测试）
    func reset() {
        lock.lock()
        actions.removeAll()
        modules.removeAll()
        lock.unlock()
    }
}
