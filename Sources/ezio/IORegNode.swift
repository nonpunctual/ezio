// IORegNode.swift — Data model for the IORegistry tree

enum IORegValue {
    case bool(Bool)
    case int(Int64)
    case float(Double)
    case string(String)
    case data([UInt8])
    indirect case array([IORegValue])
    indirect case dict([String: IORegValue])
}

struct IORegNode {
    let name: String
    let ioClass: String
    let id: UInt64
    let properties: [String: IORegValue]
    let children: [IORegNode]
}

struct NodeContext {
    let node: IORegNode
    let plane: String
    let breadcrumb: [String]          // node names from plane root down to this node
    let matchedPropertyKeys: [String] // non-empty when matched via property key in implicit search

    init(node: IORegNode, plane: String, breadcrumb: [String], matchedPropertyKeys: [String] = []) {
        self.node = node
        self.plane = plane
        self.breadcrumb = breadcrumb
        self.matchedPropertyKeys = matchedPropertyKeys
    }

    var breadcrumbString: String {
        ([plane] + breadcrumb).joined(separator: " > ")
    }
}
