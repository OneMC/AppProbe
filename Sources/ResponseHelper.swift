// ResponseHelper.swift
// AppProbe
//
// ActionResponse → GCDWebServerResponse 转换。
// 统一处理 JSON 编码、二进制响应、错误响应。

import Foundation
import GCDWebServer
import os

private let logger = Logger(subsystem: "com.appprobe", category: "response")

/// 将 ActionResponse 转换为 GCDWebServerResponse
enum ResponseHelper {

    /// 将 ActionResponse 转换为 HTTP 响应
    static func convert(_ response: ActionResponse) -> GCDWebServerResponse? {
        switch response {
        case .json(let value):
            return jsonResponse(value, statusCode: 200)
        case .jsonWithStatus(let value, let statusCode):
            return jsonResponse(value, statusCode: statusCode)
        case .raw(let data, let contentType, let headers):
            let resp = GCDWebServerDataResponse(data: data, contentType: contentType)
            for (key, value) in headers {
                resp.setValue(value, forAdditionalHeader: key)
            }
            return resp
        case .error(let code, let message):
            return errorResponse(code, message)
        }
    }

    /// 将 Codable 对象编码为 JSON 响应
    static func jsonResponse(_ value: any Codable, statusCode: Int) -> GCDWebServerResponse? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        do {
            let data = try encoder.encode(value)
            let response = GCDWebServerDataResponse(data: data, contentType: "application/json; charset=utf-8")
            response.statusCode = statusCode
            return response
        } catch {
            logger.error("[response] JSON 编码失败: \(error.localizedDescription)")
            return errorResponse(500, "JSON encoding failed: \(error.localizedDescription)")
        }
    }

    /// 构建错误响应
    static func errorResponse(_ statusCode: Int, _ message: String) -> GCDWebServerResponse? {
        let errorDict: [String: Any] = [
            "error": message,
            "statusCode": statusCode
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: errorDict, options: .prettyPrinted)
            let response = GCDWebServerDataResponse(data: data, contentType: "application/json; charset=utf-8")
            response.statusCode = statusCode
            return response
        } catch {
            guard let fallbackResponse = GCDWebServerDataResponse(text: "Internal Server Error: \(message)") else {
                return nil
            }
            fallbackResponse.statusCode = statusCode
            return fallbackResponse
        }
    }
}
