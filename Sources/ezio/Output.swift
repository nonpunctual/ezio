// Output.swift — Format and print evaluation results

import Foundation

// MARK: - Main render entry point

enum RenderOutcome {
    case rendered
    case noMatches
    case noScalar  // matches were found but -S has no property-key value to extract
}

func renderResult(_ result: EvalResult, showProperties: Bool, showChildren: Bool, foldChildren: Bool, stringOnly: Bool = false) -> RenderOutcome {
    switch result {
    case .nodes(let contexts):
        if contexts.isEmpty { return .noMatches }
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
            return printed ? .rendered : .noScalar
        }
        for (i, ctx) in contexts.enumerated() {
            if i > 0 { print("") }
            renderNodeContext(ctx, showProperties: showProperties, showChildren: showChildren, foldChildren: foldChildren)
        }
        if contexts.count > 1 {
            print("\n\(contexts.count) results.")
        }
        return .rendered

    case .propertyValues(let results):
        if results.isEmpty { return .noMatches }
        if stringOnly {
            for result in results {
                print(rawString(result.value))
            }
            return .rendered
        }
        for (i, result) in results.enumerated() {
            if i > 0 { print("") }
            print("\(result.context.breadcrumbString)/@\(result.key)")
            print("  \(formatValue(result.value, indent: 2))")
        }
        if results.count > 1 {
            print("\n\(results.count) results.")
        }
        return .rendered
    }
}

// MARK: - Shared formatting helpers

// UInt64-safe hex formatting — %x reads a 32-bit value and truncates ids above 2^32.
func idHex(_ id: UInt64) -> String {
    String(format: "0x%llx", id)
}

// One line of a folded, enumerated child listing: "  1  name...  <class>  (N children)"
func foldedChildLine(index: Int, child: IORegNode) -> String {
    let deeper = child.children.isEmpty ? "" : "  (\(child.children.count) children)"
    let paddedName = child.name.padding(toLength: 40, withPad: " ", startingAt: 0)
    return String(format: "  %3d  %@  <%@>%@", index, paddedName, child.ioClass, deeper)
}

// Print a node's properties bag, matching the "Properties (N):" / "(none)" header style.
func printPropertiesBlock(_ node: IORegNode) {
    let props = node.properties.sortedByKey()
    if props.isEmpty {
        print("  Properties: (none)")
    } else {
        print("  Properties (\(props.count)):")
        for (key, value) in props {
            print("    \(key): \(formatValue(value, indent: 6))")
        }
    }
}

// MARK: - Node identity block

private func renderNodeContext(_ ctx: NodeContext, showProperties: Bool, showChildren: Bool, foldChildren: Bool) {
    print("\(ctx.node.name) <\(ctx.node.ioClass)> [\(idHex(ctx.node.id))]")
    print("  \(ctx.breadcrumbString)")

    // Show matched property keys (from implicit/discovery search or a property predicate)
    for key in ctx.matchedPropertyKeys {
        if let val = ctx.node.properties[key] {
            print("  \(key) = \(formatValue(val, indent: 4))")
        }
    }

    if showProperties {
        printPropertiesBlock(ctx.node)
    }

    if showChildren {
        let children = ctx.node.children
        if children.isEmpty {
            print("  Children: (none)")
        } else {
            print("  Children (\(children.count)):")
            if foldChildren {
                for (i, child) in children.enumerated() {
                    print(foldedChildLine(index: i + 1, child: child))
                }
            } else {
                renderChildTree(children, indent: 4)
            }
        }
    }
}

private func renderChildTree(_ nodes: [IORegNode], indent: Int) {
    let pad = String(repeating: " ", count: indent)
    for node in nodes {
        print("\(pad)\(node.name) <\(node.ioClass)> [\(idHex(node.id))]")
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
        let inner = pairs.sortedByKey()
            .map { "\(pad)\($0.key): \(formatValue($0.value, indent: indent + 2))" }
            .joined(separator: ",\n")
        return "{\n\(inner)\n\(closePad)}"
    }
}
