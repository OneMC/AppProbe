// ViewActions.swift
// AppProbe
//
// 视图检查 Actions：Hierarchy、Highlight、Screenshot

import Foundation

// MARK: - ViewHierarchyAction

/// GET /view/hierarchy — 查找并检查视图
final class ViewHierarchyAction: AIAction {
    let module = "view"
    let name = "hierarchy"
    let httpMethod = "GET"
    let summary = "查找并检查指定视图的属性和层级树；无参数时返回 keyWindow 完整层级"
    let parameters = [
        APIParameterDescriptor(name: "tag", type: "Int", required: false, description: "通过 tag 查找视图"),
        APIParameterDescriptor(name: "class", type: "String", required: false, description: "通过类名查找视图（如 UILabel、UIButton）"),
        APIParameterDescriptor(name: "address", type: "String", required: false, description: "通过内存地址查找视图（如 0x7f8b1c005a00）"),
        APIParameterDescriptor(name: "includeSubviews", type: "Bool", required: false, description: "是否包含子视图层级树，默认 true"),
        APIParameterDescriptor(name: "maxDepth", type: "Int", required: false, description: "层级树最大递归深度，默认 15。设为 0 不限制"),
    ]
    let example = APIExample(
        requestURL: "/view/hierarchy?tag=100",
        responseBody: ##"{"found":true,"target":{"address":"0x100800000","className":"UILabel","tag":100,"frame":{"x":20,"y":20,"width":200,"height":44},"bounds":{"x":0,"y":0,"width":200,"height":44},"center":{"x":120,"y":42},"alpha":1,"isHidden":false,"isUserInteractionEnabled":true,"backgroundColor":null,"tintColor":"#007AFF","layerInfo":{"cornerRadius":0,"borderWidth":0,"borderColor":null,"shadowColor":null,"shadowOffset":{"width":0,"height":-3},"shadowRadius":3,"shadowOpacity":0},"constraints":[]},"hierarchy":{"depth":1,"subviewCount":0,"tree":{"className":"UILabel","address":"0x100800000","tag":100,"frame":{"x":20,"y":20,"width":200,"height":44},"alpha":1,"isHidden":false,"subviews":[],"labelInfo":{"text":"Hello","font":{"name":".SFUI-Regular","size":17},"textColor":"#000000","textAlignment":"natural"},"imageViewInfo":null,"buttonInfo":null}},"error":null,"searched":{"tag":100,"className":null,"address":null,"windowCount":1,"totalViewsScanned":42}}"##
    )

    func execute(params: [String: String]) -> ActionResponse {
        let tag = params["tag"].flatMap { Int($0) }
        let className = params["class"]
        let address = params["address"]
        let includeSubviews = params["includeSubviews"]?.lowercased() != "false"
        let maxDepth: Int?
        if let depthStr = params["maxDepth"], let d = Int(depthStr) {
            maxDepth = d == 0 ? nil : d
        } else {
            maxDepth = 15
        }

        return ViewActionHelper.inspectView(
            tag: tag, className: className, address: address,
            includeSubviews: includeSubviews, maxDepth: maxDepth
        )
    }
}

// MARK: - ViewHighlightAction

/// GET /view/highlight — 高亮视图并截图
final class ViewHighlightAction: AIAction {
    let module = "view"
    let name = "highlight"
    let httpMethod = "GET"
    let summary = "给指定视图添加临时高亮边框并返回截图（直接返回图片二进制，Content-Type: image/jpeg；元数据通过 X-Image-* 响应头返回）"
    let parameters = [
        APIParameterDescriptor(name: "tag", type: "Int", required: false, description: "通过 tag 查找视图（与 address 二选一）"),
        APIParameterDescriptor(name: "address", type: "String", required: false, description: "通过内存地址查找视图（与 tag 二选一）"),
        APIParameterDescriptor(name: "borderColor", type: "String", required: false, description: "高亮边框颜色，Hex 格式（如 FF0000），默认红色"),
        APIParameterDescriptor(name: "borderWidth", type: "Double", required: false, description: "高亮边框宽度，默认 2"),
        APIParameterDescriptor(name: "quality", type: "Double", required: false, description: "JPEG 压缩质量 (0.0-1.0)，默认 0.75"),
        APIParameterDescriptor(name: "scale", type: "Double", required: false, description: "渲染缩放比例 (0.1-3.0)，默认 1.0"),
        APIParameterDescriptor(name: "format", type: "String", required: false, description: "图片格式：jpeg（默认）或 png"),
    ]
    let example = APIExample(
        requestURL: "/view/highlight?tag=100",
        responseBody: "<raw image binary; use curl -o file.jpg to save; headers: X-Image-Width, X-Image-Height, X-Original-Width, X-Original-Height, X-Image-Format, X-Image-Quality, X-Image-Scale>"
    )

    func execute(params: [String: String]) -> ActionResponse {
        return ViewActionHelper.highlightAndCapture(
            tag: params["tag"].flatMap { Int($0) },
            address: params["address"],
            borderColorHex: params["borderColor"],
            borderWidth: params["borderWidth"].flatMap { Double($0) },
            quality: params["quality"].flatMap { Double($0) },
            scale: params["scale"].flatMap { Double($0) },
            format: params["format"]
        )
    }
}

// MARK: - ViewScreenshotAction

/// GET /view/screenshot — 截取视图截图
final class ViewScreenshotAction: AIAction {
    let module = "view"
    let name = "screenshot"
    let httpMethod = "GET"
    let summary = "截取指定视图的截图并直接返回图片二进制；无参数时截取 keyWindow"
    let parameters = [
        APIParameterDescriptor(name: "tag", type: "Int", required: false, description: "通过 tag 查找视图（三选一）"),
        APIParameterDescriptor(name: "class", type: "String", required: false, description: "通过类名查找视图（三选一）"),
        APIParameterDescriptor(name: "address", type: "String", required: false, description: "通过内存地址查找视图（三选一）"),
        APIParameterDescriptor(name: "quality", type: "Double", required: false, description: "JPEG 压缩质量 (0.0-1.0)，默认 0.75"),
        APIParameterDescriptor(name: "scale", type: "Double", required: false, description: "渲染缩放比例 (0.1-3.0)，默认 1.0"),
        APIParameterDescriptor(name: "format", type: "String", required: false, description: "图片格式：jpeg（默认）或 png"),
    ]
    let example = APIExample(
        requestURL: "/view/screenshot?tag=100&quality=0.8",
        responseBody: "<raw image binary; use curl -o file.jpg to save; headers: X-Image-Width, X-Image-Height, X-Original-Width, X-Original-Height, X-Image-Format, X-Image-Quality, X-Image-Scale>"
    )

    func execute(params: [String: String]) -> ActionResponse {
        return ViewActionHelper.captureScreenshot(
            tag: params["tag"].flatMap { Int($0) },
            className: params["class"],
            address: params["address"],
            quality: params["quality"].flatMap { Double($0) },
            scale: params["scale"].flatMap { Double($0) },
            format: params["format"]
        )
    }
}
