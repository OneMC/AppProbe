// SystemActions.swift
// AppProbe
//
// 系统管理 Actions：Catalog（API 目录）、Status（服务器状态）

import UIKit
import os

private let logger = Logger(subsystem: "com.appprobe", category: "system-actions")

// MARK: - Catalog Response Models

/// GET /catalog?module=xxx 响应 — 简洁列表
struct CatalogListResponse: Codable {
    let hint: CatalogHint
    let apiCount: Int
    let apis: [CatalogListItem]
}

struct CatalogListItem: Codable {
    let path: String
    let method: String
    let summary: String
    let module: String
}

/// GET /catalog/detail 响应 — 完整详情
struct CatalogDetailResponse: Codable {
    let path: String
    let method: String
    let summary: String
    let module: String
    let parameters: [APIParameterDescriptor]
    let example: APIExample
}

/// GET /catalog 无参数时的响应 — module 概览
struct ModuleOverviewResponse: Codable {
    let moduleCount: Int
    let hint: CatalogHint
    let modules: [ModuleOverviewItem]
}

struct CatalogHint: Codable {
    let listApis: String
    let getDetail: String
}

struct ModuleOverviewItem: Codable {
    let name: String
    let description: String
    let apiCount: Int
    let listApis: String?
    let apis: [SystemAPIItem]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(apiCount, forKey: .apiCount)
        try container.encodeIfPresent(listApis, forKey: .listApis)
        try container.encodeIfPresent(apis, forKey: .apis)
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, apiCount, listApis, apis
    }
}

struct SystemAPIItem: Codable {
    let path: String
    let method: String
    let summary: String
    let parameters: [APIParameterDescriptor]
}

// MARK: - CatalogAction

/// GET /catalog — API 目录查询
final class CatalogAction: AIAction {
    let module = "catalog"
    let name = ""
    let httpMethod = "GET"
    let summary = "获取 API 目录：无参数返回 module 概览；?module=xxx 返回该模块下的 API；?module=all 返回全部"
    let parameters = [
        APIParameterDescriptor(name: "module", type: "String", required: false,
                               description: "模块名称，传 all 返回全部 API，不传返回 module 概览"),
    ]
    let example = APIExample(
        requestURL: "/catalog?module=all",
        responseBody: #"{"apiCount":2,"apis":[{"path":"/catalog","method":"GET","summary":"获取 API 目录","module":"catalog"},{"path":"/status","method":"GET","summary":"获取服务器和 App 基本状态信息","module":"status"}]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        let moduleParam = params["module"]

        let catalogHint = CatalogHint(
            listApis: "GET /catalog?module={name} — 获取指定 module 下的全部 API 列表",
            getDetail: "GET /catalog/detail?path={api_path} — 获取指定 API 的完整使用说明（参数定义和请求示例）"
        )

        if let moduleParam = moduleParam {
            if moduleParam == "all" {
                let allActions = APIRegistry.shared.allActions()
                let items = allActions.map {
                    CatalogListItem(path: $0.path, method: $0.httpMethod,
                                    summary: $0.summary, module: $0.module)
                }
                return .json(CatalogListResponse(hint: catalogHint, apiCount: items.count, apis: items))
            } else {
                let moduleActions = APIRegistry.shared.actions(forModule: moduleParam)
                if moduleActions.isEmpty {
                    let allModules = APIRegistry.shared.allModules()
                    if !allModules.contains(where: { $0.name == moduleParam }) {
                        return .error(code: 404, message: "Module not found: \(moduleParam)")
                    }
                }
                let items = moduleActions.map {
                    CatalogListItem(path: $0.path, method: $0.httpMethod,
                                    summary: $0.summary, module: $0.module)
                }
                return .json(CatalogListResponse(hint: catalogHint, apiCount: items.count, apis: items))
            }
        } else {
            // 无参数 → module 概览
            let allModules = APIRegistry.shared.allModules()
            let overviewItems = allModules.map { mod -> ModuleOverviewItem in
                let modActions = APIRegistry.shared.actions(forModule: mod.name)
                if mod.name == "catalog" || mod.name == "status" {
                    // system-level modules: show full API info
                    let apis = modActions.map {
                        SystemAPIItem(path: $0.path, method: $0.httpMethod,
                                      summary: $0.summary, parameters: $0.parameters)
                    }
                    return ModuleOverviewItem(
                        name: mod.name, description: mod.description,
                        apiCount: modActions.count, listApis: nil, apis: apis
                    )
                } else {
                    return ModuleOverviewItem(
                        name: mod.name, description: mod.description,
                        apiCount: modActions.count,
                        listApis: "GET /catalog?module=\(mod.name)", apis: nil
                    )
                }
            }
            return .json(ModuleOverviewResponse(
                moduleCount: overviewItems.count, hint: catalogHint, modules: overviewItems
            ))
        }
    }
}

// MARK: - CatalogDetailAction

/// GET /catalog/detail — 获取指定 API 的完整使用说明
final class CatalogDetailAction: AIAction {
    let module = "catalog"
    let name = "detail"
    let httpMethod = "GET"
    let summary = "获取指定 API 的完整使用说明，包含参数列表和示例。必传参数: path"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true,
                               description: "要查询的 API 路径，如 /view/hierarchy"),
    ]
    let example = APIExample(
        requestURL: "/catalog/detail?path=/status",
        responseBody: #"{"path":"/status","method":"GET","summary":"获取服务器和 App 基本状态信息","module":"status","parameters":[],"example":{"requestURL":"/status","responseBody":"{\"status\":\"ok\"}"}}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"] else {
            return .error(code: 400, message: "Missing 'path' query parameter")
        }

        guard let action = APIRegistry.shared.action(forPath: path) else {
            return .error(code: 404, message: "API not found: \(path)")
        }

        let detail = CatalogDetailResponse(
            path: action.path,
            method: action.httpMethod,
            summary: action.summary,
            module: action.module,
            parameters: action.parameters,
            example: action.example
        )
        return .json(detail)
    }
}

// MARK: - StatusAction

/// GET /status — 服务器和 App 基本状态
final class StatusAction: AIAction {
    let module = "status"
    let name = ""
    let httpMethod = "GET"
    let summary = "获取服务器和 App 基本状态信息"
    let parameters: [APIParameterDescriptor] = []
    let example = APIExample(
        requestURL: "/status",
        responseBody: #"{"status":"ok","serverVersion":"1.0.0","appName":"TestDEMO","device":"iPhone","windowCount":1}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        var result: ActionResponse = .error(code: 500, message: "Failed to get status")

        let block = {
            let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Unknown"
            let device = UIDevice.current.name
            let windowCount = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .reduce(0) { $0 + $1.windows.count }

            let status = StatusResponse(
                status: "ok",
                serverVersion: "1.0.0",
                appName: appName,
                device: device,
                windowCount: windowCount
            )
            result = .json(status)
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync { block() }
        }

        return result
    }
}
