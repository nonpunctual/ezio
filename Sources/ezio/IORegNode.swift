// IORegNode.swift — Data model for the IORegistry tree
import Foundation

enum IORegValue {
    case bool(Bool)
    case int(Int64)
    case float(Double)
    case string(String)
    case data([UInt8])
    indirect case array([IORegValue])
    indirect case dict([String: IORegValue])
}

// Decode raw bytes as a UTF-8 string (null-terminated), or nil if binary
func decodeBytesAsString(_ bytes: [UInt8]) -> String? {
    let stripped = bytes.last == 0 ? Array(bytes.dropLast()) : bytes
    guard !stripped.isEmpty,
          let str = String(bytes: stripped, encoding: .utf8),
          str.unicodeScalars.allSatisfy({ $0.value >= 32 || $0.value == 9 })
    else { return nil }
    return str
}

// Raw string value with no quotes or decoration — for scripting use and predicate comparisons
func rawString(_ value: IORegValue) -> String {
    switch value {
    case .bool(let b):   return b ? "true" : "false"
    case .int(let i):    return "\(i)"
    case .float(let f):  return "\(f)"
    case .string(let s): return s
    case .data(let bytes):
        if let str = decodeBytesAsString(bytes) { return str }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    case .array(let items): return items.map { rawString($0) }.joined(separator: "\n")
    case .dict(let pairs):
        return pairs.sortedByKey()
            .map { "\($0.key)=\(rawString($0.value))" }
            .joined(separator: "\n")
    }
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
    var matchedPropertyKeys: [String] = []  // non-empty when a property key satisfied a match

    var breadcrumbString: String {
        ([plane] + breadcrumb).joined(separator: " > ")
    }
}

extension Dictionary where Key == String {
    func sortedByKey() -> [(key: Key, value: Value)] {
        sorted { $0.key < $1.key }
    }
}

// Discovery match test shared by implicit path search (Evaluator) and shell `find`:
// matches a node whose name, class, or a property key equals `term`.
func discoveryMatch(_ node: IORegNode, term: String) -> (matched: Bool, propertyKeys: [String]) {
    let nameOrClassMatch = node.name == term || node.ioClass == term
    let matchedKeys: [String] = node.properties[term] != nil ? [term] : []
    return (nameOrClassMatch || !matchedKeys.isEmpty, matchedKeys)
}

// Walks all descendants of `node` (not including `node` itself) depth-first,
// calling `visit` for every node along with its breadcrumb path from `startBreadcrumb`.
func walkDescendants(of node: IORegNode, startBreadcrumb: [String], visit: (IORegNode, [String]) -> Void) {
    for child in node.children {
        let crumb = startBreadcrumb + [child.name]
        visit(child, crumb)
        walkDescendants(of: child, startBreadcrumb: crumb, visit: visit)
    }
}
