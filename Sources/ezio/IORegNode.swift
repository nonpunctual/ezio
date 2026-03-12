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
    let breadcrumb: [String]
    var matchedPropertyKeys: [String] = []  // non-empty when matched via property key in implicit search

    var breadcrumbString: String {
        ([plane] + breadcrumb).joined(separator: " > ")
    }
}

extension Dictionary where Key == String {
    func sortedByKey() -> [(key: Key, value: Value)] {
        sorted { $0.key < $1.key }
    }
}
