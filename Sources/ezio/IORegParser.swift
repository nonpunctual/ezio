// IORegParser.swift — Parse ioreg plist output into an IORegNode tree
import Foundation
import CoreFoundation

enum IORegParserError: Error, CustomStringConvertible {
    case invalidFormat
    case missingRoot

    var description: String {
        switch self {
        case .invalidFormat: return "ioreg output is not a recognized plist format"
        case .missingRoot:   return "ioreg output contains no root node"
        }
    }
}

private let metaKeys: Set<String> = [
    "IORegistryEntryName",
    "IOObjectClass",
    "IORegistryEntryID",
    "IORegistryEntryChildren",
]

func parsePlane(data: Data) throws -> IORegNode {
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    if let arr = plist as? [[String: Any]] {
        guard let first = arr.first else { throw IORegParserError.missingRoot }
        return try parseNode(first)
    } else if let dict = plist as? [String: Any] {
        return try parseNode(dict)
    } else {
        throw IORegParserError.invalidFormat
    }
}

private func parseNode(_ dict: [String: Any]) throws -> IORegNode {
    let name = (dict["IORegistryEntryName"] as? String)
        ?? (dict["IOObjectClass"] as? String)
        ?? "<unnamed>"
    let ioClass = (dict["IOObjectClass"] as? String) ?? "<unknown>"

    let id: UInt64
    if let raw = dict["IORegistryEntryID"] as? Int {
        id = UInt64(bitPattern: Int64(raw))
    } else {
        id = 0
    }

    var properties: [String: IORegValue] = [:]
    for (key, value) in dict where !metaKeys.contains(key) {
        properties[key] = parseValue(value)
    }

    var children: [IORegNode] = []
    if let childDicts = dict["IORegistryEntryChildren"] as? [[String: Any]] {
        children = try childDicts.map { try parseNode($0) }
    }

    return IORegNode(
        name: name,
        ioClass: ioClass,
        id: id,
        properties: properties,
        children: children
    )
}

private func parseValue(_ value: Any) -> IORegValue {
    // Bool must be checked before Int — NSNumber bridges both, use CF type ID to distinguish
    if let num = value as? NSNumber {
        if CFGetTypeID(num) == CFBooleanGetTypeID() {
            return .bool(num.boolValue)
        }
        let t = String(cString: num.objCType)
        if t == "f" || t == "d" {
            return .float(num.doubleValue)
        }
        return .int(num.int64Value)
    }
    if let s = value as? String   { return .string(s) }
    if let d = value as? Data     { return .data(Array(d)) }
    if let arr = value as? [Any]  { return .array(arr.map { parseValue($0) }) }
    if let dict = value as? [String: Any] {
        return .dict(dict.mapValues { parseValue($0) })
    }
    return .string(String(describing: value))
}
