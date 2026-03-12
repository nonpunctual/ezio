// Output.swift — Format and print evaluation results

import Foundation

// MARK: - Main render entry point

func renderResult(_ result: EvalResult, showProperties: Bool, showChildren: Bool, stringOnly: Bool = false) -> Bool {
    switch result {
    case .nodes(let contexts):
        if contexts.isEmpty { return false }
        if stringOnly {
            var printed = false
            for ctx in contexts {
                for key in ctx.matchedPropertyKeys {
                    if let val = ctx.node.properties[key] {
                        print(rawString(val))
                        printed = true
                    }
                }
            }
            if printed { return true }
            // No property keys matched (name/class match) — fall through to normal rendering
        }
        for (i, ctx) in contexts.enumerated() {
            if i > 0 { print("") }
            renderNodeContext(ctx, showProperties: showProperties, showChildren: showChildren)
        }
        if contexts.count > 1 {
            print("\n\(contexts.count) results.")
        }
        return true

    case .propertyValues(let results):
        if results.isEmpty { return false }
        if stringOnly {
            for result in results {
                print(rawString(result.value))
            }
            return true
        }
        for (i, result) in results.enumerated() {
            if i > 0 { print("") }
            print("\(result.context.breadcrumbString)/@\(result.key)")
            print("  \(formatValue(result.value, indent: 2))")
        }
        if results.count > 1 {
            print("\n\(results.count) results.")
        }
        return true
    }
}

// Decode raw bytes as a UTF-8 string (null-terminated), or nil if binary
private func decodeBytesAsString(_ bytes: [UInt8]) -> String? {
    let stripped = bytes.last == 0 ? Array(bytes.dropLast()) : bytes
    guard !stripped.isEmpty,
          let str = String(bytes: stripped, encoding: .utf8),
          str.unicodeScalars.allSatisfy({ $0.value >= 32 || $0.value == 9 })
    else { return nil }
    return str
}

// Raw string value with no quotes or decoration — for scripting use
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
        return pairs.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(rawString($0.value))" }
            .joined(separator: "\n")
    }
}

// MARK: - Node identity block

private func renderNodeContext(_ ctx: NodeContext, showProperties: Bool, showChildren: Bool) {
    let idStr = String(format: "0x%x", ctx.node.id)
    print("\(ctx.node.name) <\(ctx.node.ioClass)> [\(idStr)]")
    print("  \(ctx.breadcrumbString)")

    // Show matched property keys (from implicit/discovery search)
    for key in ctx.matchedPropertyKeys {
        if let val = ctx.node.properties[key] {
            print("  \(key) = \(formatValue(val, indent: 4))")
        }
    }

    if showProperties {
        let props = ctx.node.properties.sorted { $0.key < $1.key }
        if props.isEmpty {
            print("  Properties: (none)")
        } else {
            print("  Properties (\(props.count)):")
            for (key, value) in props {
                let valStr = formatValue(value, indent: 6)
                print("    \(key): \(valStr)")
            }
        }
    }

    if showChildren {
        let children = ctx.node.children
        if children.isEmpty {
            print("  Children: (none)")
        } else {
            print("  Children (\(children.count)):")
            renderChildTree(children, indent: 4)
        }
    }
}

private func renderChildTree(_ nodes: [IORegNode], indent: Int) {
    let pad = String(repeating: " ", count: indent)
    for node in nodes {
        let idStr = String(format: "0x%x", node.id)
        print("\(pad)\(node.name) <\(node.ioClass)> [\(idStr)]")
        if !node.children.isEmpty {
            renderChildTree(node.children, indent: indent + 2)
        }
    }
}

// MARK: - Value formatting

func formatValue(_ value: IORegValue, indent: Int) -> String {
    switch value {
    case .bool(let b):
        return b ? "true" : "false"
    case .int(let i):
        return "\(i)"
    case .float(let f):
        return "\(f)"
    case .string(let s):
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    case .data(let bytes):
        if bytes.isEmpty { return "<empty>" }
        if let str = decodeBytesAsString(bytes) { return "\"\(str)\"" }
        let hex = bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        if bytes.count > 16 {
            return "<\(hex) ...> (\(bytes.count) bytes)"
        }
        return "<\(hex)>"
    case .array(let items):
        if items.isEmpty { return "[]" }
        if items.count == 1 { return "[ \(formatValue(items[0], indent: indent)) ]" }
        let pad = String(repeating: " ", count: indent + 2)
        let closePad = String(repeating: " ", count: indent)
        let inner = items.map { "\(pad)\(formatValue($0, indent: indent + 2))" }.joined(separator: ",\n")
        return "[\n\(inner)\n\(closePad)]"
    case .dict(let pairs):
        if pairs.isEmpty { return "{}" }
        let pad = String(repeating: " ", count: indent + 2)
        let closePad = String(repeating: " ", count: indent)
        let inner = pairs.sorted { $0.key < $1.key }
            .map { "\(pad)\($0.key): \(formatValue($0.value, indent: indent + 2))" }
            .joined(separator: ",\n")
        return "{\n\(inner)\n\(closePad)}"
    }
}
