// UserDefaultsActions.swift
// AppProbe
//
// UserDefaults 管理 Actions：Get/List、Set、Delete

import Foundation
import os

private let logger = Logger(subsystem: "com.appprobe", category: "ud-actions")

// MARK: - UDGetAction

/// GET /userDefaults — 获取或列举 UserDefaults
final class UDGetAction: AIAction {
    let module = "userDefaults"
    let name = ""
    let httpMethod = "GET"
    let summary = "获取或列举 UserDefaults 键值对；传 key 获取单个值，不传列举所有"
    let parameters = [
        APIParameterDescriptor(name: "key", type: "String", required: false, description: "精确获取指定 key 的值；不传时列举所有 key"),
        APIParameterDescriptor(name: "prefix", type: "String", required: false, description: "列举模式下，只返回以此前缀开头的 key"),
        APIParameterDescriptor(name: "search", type: "String", required: false, description: "列举模式下，只返回 key 名包含此子串的条目"),
        APIParameterDescriptor(name: "suite", type: "String", required: false, description: "自定义 suite 名称，不传时使用 UserDefaults.standard"),
    ]
    let example = APIExample(
        requestURL: "/userDefaults?prefix=feature_",
        responseBody: #"{"suite":"standard","count":2,"entries":[{"key":"feature_darkMode","type":"Bool","value":"true"},{"key":"feature_newUI","type":"Bool","value":"false"}]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        let suite = params["suite"]

        if let key = params["key"] {
            let response = SandboxInspector.shared.getUserDefault(key: key, suite: suite)
            return .json(response)
        } else {
            let prefix = params["prefix"]
            let search = params["search"]
            let result = SandboxInspector.shared.listUserDefaults(suite: suite, prefix: prefix, search: search)
            switch result {
            case .success(let listResponse):
                return .json(listResponse)
            case .failure(let error):
                return .error(code: 500, message: error.error)
            }
        }
    }
}

// MARK: - UDSetAction

/// GET /userDefaults/set — 设置 UserDefaults 值
final class UDSetAction: AIAction {
    let module = "userDefaults"
    let name = "set"
    let httpMethod = "POST"
    let summary = "设置 UserDefaults 值，支持 string/int/double/bool 类型"
    let parameters = [
        APIParameterDescriptor(name: "key", type: "String", required: true, description: "要设置的 key"),
        APIParameterDescriptor(name: "value", type: "String", required: true, description: "值（字符串表示）"),
        APIParameterDescriptor(name: "type", type: "String", required: true, description: "值类型：string / int / double / bool"),
        APIParameterDescriptor(name: "suite", type: "String", required: false, description: "自定义 suite 名称"),
    ]
    let example = APIExample(
        requestURL: "/userDefaults/set?key=feature_darkMode&value=true&type=bool",
        responseBody: #"{"success":true,"key":"feature_darkMode","type":"bool","value":"true","message":"Value set"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let key = params["key"], let value = params["value"], let type = params["type"] else {
            return .error(code: 400, message: "Missing required parameters: key, value, type")
        }
        let suite = params["suite"]
        let result = SandboxInspector.shared.setUserDefault(key: key, value: value, type: type, suite: suite)
        switch result {
        case .success(let response):
            return .json(response)
        case .failure(let error):
            return .error(code: 400, message: error.error)
        }
    }
}

// MARK: - UDDeleteAction

/// GET /userDefaults/delete — 删除 UserDefaults 键
final class UDDeleteAction: AIAction {
    let module = "userDefaults"
    let name = "delete"
    let httpMethod = "POST"
    let summary = "删除 UserDefaults 中的指定 key"
    let parameters = [
        APIParameterDescriptor(name: "key", type: "String", required: true, description: "要删除的 key"),
        APIParameterDescriptor(name: "suite", type: "String", required: false, description: "自定义 suite 名称"),
    ]
    let example = APIExample(
        requestURL: "/userDefaults/delete?key=feature_darkMode",
        responseBody: #"{"success":true,"key":"feature_darkMode","message":"Key removed"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let key = params["key"] else {
            return .error(code: 400, message: "Missing 'key' parameter")
        }
        let suite = params["suite"]
        let response = SandboxInspector.shared.deleteUserDefault(key: key, suite: suite)
        return .json(response)
    }
}
