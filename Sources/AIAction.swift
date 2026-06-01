// AIAction.swift
// AppProbe
//
// 统一 API 注册协议。所有 API（内置和业务）通过实现此协议注册。

import Foundation

// MARK: - Metadata Models

/// API 参数描述
public struct APIParameterDescriptor: Codable {
    public let name: String
    public let type: String
    public let required: Bool
    public let description: String

    public init(name: String, type: String, required: Bool, description: String) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
    }
}

/// API 使用示例
public struct APIExample: Codable {
    public let requestURL: String
    public let responseBody: String

    public init(requestURL: String, responseBody: String) {
        self.requestURL = requestURL
        self.responseBody = responseBody
    }
}

/// Module 描述符
public struct ModuleDescriptor: Codable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

// MARK: - Action Response

/// 统一动作执行结果
public enum ActionResponse {
    /// JSON 响应（HTTP 200）
    case json(any Codable)
    /// JSON 响应（自定义 HTTP 状态码，用于非 200 的 JSON 响应如 404 not found）
    case jsonWithStatus(any Codable, statusCode: Int)
    /// 原始二进制响应（图片等），附带自定义 HTTP headers
    case raw(data: Data, contentType: String, headers: [String: String])
    /// 简单错误响应（生成 {"error":message,"statusCode":code}）
    case error(code: Int, message: String)
}

/// 通用动作执行结果（业务模块常用）
public struct ActionResult: Codable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

// MARK: - AIAction Protocol

/// 统一 API 注册协议
///
/// 所有 API（内置和业务）通过实现此协议向 AppProbe 注册。
/// 路径推导规则：name 为空 → "/{module}"，否则 → "/{module}/{name}"
public protocol AIAction: AnyObject {
    /// 模块名，单个单词，路径第一段。如 "view", "sandbox", "homepage"
    /// 约束：必须为 [a-zA-Z][a-zA-Z0-9]* ，不能包含 "/"
    var module: String { get }
    /// 动作标识，可为空或多层 path。如 "hierarchy", "catalog/detail", ""
    var name: String { get }
    /// HTTP 方法：GET / POST
    var httpMethod: String { get }
    /// 一句话描述，出现在 catalog 列表中
    var summary: String { get }
    /// 参数定义列表
    var parameters: [APIParameterDescriptor] { get }
    /// 使用示例
    var example: APIExample { get }
    /// 执行动作
    func execute(params: [String: String]) -> ActionResponse
}

extension AIAction {
    /// 从 module + name 自动推导 HTTP 路径
    public var path: String {
        if name.isEmpty {
            return "/\(module)"
        }
        return "/\(module)/\(name)"
    }
}
