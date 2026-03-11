// IORegNode.swift — Data model for the IORegistry tree

indirect enum IORegValue {
    case bool(Bool)
    case int(Int64)
    case float(Double)
    case string(String)
    case data([UInt8])
    case array([IORegValue])
    case dict([String: IORegValue])
}

struct IORegNode {
    var name: String
    var ioClass: String
    var id: UInt64
    var properties: [String: IORegValue]
    var children: [IORegNode]
}

struct NodeContext {
    var node: IORegNode
    var plane: String
    var breadcrumb: [String]          // node names from plane root down to this node
    var matchedPropertyKeys: [String] // non-empty when matched via property key in implicit search

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
