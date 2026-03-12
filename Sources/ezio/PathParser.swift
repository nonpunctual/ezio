// PathParser.swift — Tokenize and parse XPath-style path expressions

let planeOrder: [String] = ["IOService", "IOPower", "IODeviceTree", "IOUSB", "IOAudio", "IOFireWire"]
let knownPlanes: Set<String> = Set(planeOrder)

// MARK: - AST types

struct PathExpr {
    var plane: String
    var steps: [PathStep]
    var propertySelect: String?
    var isImplicitSearch: Bool = false
    var implicitTerm: String?   // the bare search term, for three-dimension discovery
}

enum PathStep {
    case direct(NodeMatcher, [Predicate])
    case recursive(NodeMatcher, [Predicate])
}

enum NodeMatcher {
    case name(String)
    case wildcard
}

enum Predicate {
    case classEquals(String)
    case classContains(String)
    case idEquals(UInt64)
    case nameContains(String)
    case propertyExists(String)
    case propertyEquals(String, String)
    case position(Int)  // [n] — select nth child (1-based)
}

// MARK: - Errors

enum PathError: Error, CustomStringConvertible {
    case empty
    case unexpectedCharacter(Character)
    case unexpectedToken(String)
    case expectedName
    case expectedStringValue
    case expectedRBracket
    case expectedRParen
    case expectedLParen
    case expectedComma
    case expectedAt
    case invalidPredicate(String)

    var description: String {
        switch self {
        case .empty:                    return "empty path"
        case .unexpectedCharacter(let c): return "unexpected character '\(c)'"
        case .unexpectedToken(let t):   return "unexpected token '\(t)'"
        case .expectedName:             return "expected a name or wildcard"
        case .expectedStringValue:      return "expected a string value"
        case .expectedRBracket:         return "expected ']'"
        case .expectedRParen:           return "expected ')'"
        case .expectedLParen:           return "expected '('"
        case .expectedComma:            return "expected ','"
        case .expectedAt:               return "expected '@'"
        case .invalidPredicate(let m):  return "invalid predicate: \(m)"
        }
    }
}

// MARK: - Tokens

private enum Token: Equatable {
    case slash
    case doubleSlash
    case at
    case asterisk
    case openBracket
    case closeBracket
    case openParen
    case closeParen
    case equals
    case comma
    case identifier(String)
    case quotedString(String)
    case hexNumber(UInt64)
}

// MARK: - Tokenizer

private func tokenize(_ input: String) throws -> [Token] {
    var tokens: [Token] = []
    var i = input.startIndex

    while i < input.endIndex {
        let ch = input[i]
        switch ch {
        case "/":
            let j = input.index(after: i)
            if j < input.endIndex && input[j] == "/" {
                tokens.append(.doubleSlash)
                i = input.index(after: j)
            } else {
                tokens.append(.slash)
                i = j
            }
        case "*":
            tokens.append(.asterisk)
            i = input.index(after: i)
        case "@":
            tokens.append(.at)
            i = input.index(after: i)
        case "[":
            tokens.append(.openBracket)
            i = input.index(after: i)
        case "]":
            tokens.append(.closeBracket)
            i = input.index(after: i)
        case "(":
            tokens.append(.openParen)
            i = input.index(after: i)
        case ")":
            tokens.append(.closeParen)
            i = input.index(after: i)
        case "=":
            tokens.append(.equals)
            i = input.index(after: i)
        case ",":
            tokens.append(.comma)
            i = input.index(after: i)
        case "\"", "'":
            let quote = ch
            var j = input.index(after: i)
            var str = ""
            while j < input.endIndex && input[j] != quote {
                str.append(input[j])
                j = input.index(after: j)
            }
            if j < input.endIndex { j = input.index(after: j) }
            tokens.append(.quotedString(str))
            i = j
        case " ", "\t":
            i = input.index(after: i)
        default:
            guard ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." || ch == ":" else {
                throw PathError.unexpectedCharacter(ch)
            }
            var j = i
            var word = ""
            while j < input.endIndex {
                let c = input[j]
                if c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." || c == ":" {
                    word.append(c)
                    j = input.index(after: j)
                } else {
                    break
                }
            }
            if word.lowercased().hasPrefix("0x"),
               let val = UInt64(word.dropFirst(2), radix: 16) {
                tokens.append(.hexNumber(val))
            } else {
                tokens.append(.identifier(word))
            }
            i = j
        }
    }
    return tokens
}

// MARK: - Parser

struct PathParser {
    private let tokens: [Token]
    private var pos: Int = 0

    private var current: Token? { pos < tokens.count ? tokens[pos] : nil }
    private var atEnd: Bool { pos >= tokens.count }

    static func parse(_ input: String) throws -> PathExpr {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw PathError.empty }
        let toks = try tokenize(trimmed)
        var parser = PathParser(tokens: toks)
        return try parser.parsePath()
    }

    private mutating func advance() { pos += 1 }

    // MARK: Top-level dispatch

    private mutating func parsePath() throws -> PathExpr {
        switch current {
        case .slash:
            advance()
            return try parseAfterLeadingSlash()
        case .doubleSlash:
            advance()
            return try parseDoubleSlashRoot()
        case .identifier(let name):
            advance()
            // Bare name: discovery mode — matches name, class, and property keys
            let preds = try parsePredicates()
            let (moreSeps, morePropSel) = try parseMoreSteps()
            let step = PathStep.recursive(.name(name), preds)
            return PathExpr(
                plane: "IOService",
                steps: [step] + moreSeps,
                propertySelect: morePropSel,
                isImplicitSearch: true,
                implicitTerm: name
            )
        case .asterisk:
            advance()
            let preds = try parsePredicates()
            let (more, propSel) = try parseMoreSteps()
            return PathExpr(
                plane: "IOService",
                steps: [.recursive(.wildcard, preds)] + more,
                propertySelect: propSel,
                isImplicitSearch: false,
                implicitTerm: nil
            )
        case .openBracket:
            // [ClassName] bare top-level — class-only recursive search in IOService
            let preds = try parsePredicates()
            let (more, propSel) = try parseMoreSteps()
            return PathExpr(
                plane: "IOService",
                steps: [.recursive(.wildcard, preds)] + more,
                propertySelect: propSel,
                isImplicitSearch: false,
                implicitTerm: nil
            )
        default:
            throw PathError.expectedName
        }
    }

    // Called after consuming the opening /
    private mutating func parseAfterLeadingSlash() throws -> PathExpr {
        if atEnd {
            // Just "/" — show IOService root
            return PathExpr(plane: "IOService", steps: [], propertySelect: nil, isImplicitSearch: false)
        }
        switch current {
        case .identifier(let first):
            advance()
            if knownPlanes.contains(first) {
                return try parseAfterPlane(first)
            }
            // /someName — direct child of IOService root
            let preds = try parsePredicates()
            var steps: [PathStep] = [.direct(.name(first), preds)]
            let (more, propSel) = try parseMoreSteps()
            steps += more
            return PathExpr(plane: "IOService", steps: steps, propertySelect: propSel, isImplicitSearch: false)
        case .asterisk:
            advance()
            let preds = try parsePredicates()
            var steps: [PathStep] = [.direct(.wildcard, preds)]
            let (more, propSel) = try parseMoreSteps()
            steps += more
            return PathExpr(plane: "IOService", steps: steps, propertySelect: propSel, isImplicitSearch: false)
        case .at:
            // /@prop — property on IOService root
            advance()
            guard case .identifier(let p)? = current else { throw PathError.expectedName }
            advance()
            return PathExpr(plane: "IOService", steps: [], propertySelect: p, isImplicitSearch: false)
        default:
            throw PathError.expectedName
        }
    }

    // Called after consuming // at the start
    private mutating func parseDoubleSlashRoot() throws -> PathExpr {
        let step = try parseNameOrWildcard(recursive: true)
        var steps = [step]
        let (more, propSel) = try parseMoreSteps()
        steps += more
        return PathExpr(plane: "IOService", steps: steps, propertySelect: propSel, isImplicitSearch: false)
    }

    // Called after consuming /PlaneName
    private mutating func parseAfterPlane(_ plane: String) throws -> PathExpr {
        if atEnd {
            return PathExpr(plane: plane, steps: [], propertySelect: nil, isImplicitSearch: false)
        }
        switch current {
        case .slash:
            advance()
            if case .at? = current {
                // /Plane/@prop
                advance()
                guard case .identifier(let p)? = current else { throw PathError.expectedName }
                advance()
                return PathExpr(plane: plane, steps: [], propertySelect: p, isImplicitSearch: false)
            }
            let step = try parseNameOrWildcard(recursive: false)
            var steps = [step]
            let (more, propSel) = try parseMoreSteps()
            steps += more
            return PathExpr(plane: plane, steps: steps, propertySelect: propSel, isImplicitSearch: false)
        case .doubleSlash:
            advance()
            let step = try parseNameOrWildcard(recursive: true)
            var steps = [step]
            let (more, propSel) = try parseMoreSteps()
            steps += more
            return PathExpr(plane: plane, steps: steps, propertySelect: propSel, isImplicitSearch: false)
        default:
            return PathExpr(plane: plane, steps: [], propertySelect: nil, isImplicitSearch: false)
        }
    }

    // Parse additional /step or //step sequences after the first step
    private mutating func parseMoreSteps() throws -> ([PathStep], String?) {
        var steps: [PathStep] = []

        while !atEnd {
            switch current {
            case .slash:
                advance()
                if case .at? = current {
                    // /@prop — terminal property selector
                    advance()
                    guard case .identifier(let p)? = current else { throw PathError.expectedName }
                    advance()
                    return (steps, p)
                } else if !atEnd {
                    let step = try parseNameOrWildcard(recursive: false)
                    steps.append(step)
                }
            case .doubleSlash:
                advance()
                let step = try parseNameOrWildcard(recursive: true)
                steps.append(step)
            default:
                return (steps, nil)
            }
        }
        return (steps, nil)
    }

    private mutating func parseNameOrWildcard(recursive: Bool) throws -> PathStep {
        switch current {
        case .asterisk:
            advance()
            let preds = try parsePredicates()
            return recursive ? .recursive(.wildcard, preds) : .direct(.wildcard, preds)
        case .identifier(let n):
            advance()
            let preds = try parsePredicates()
            return recursive ? .recursive(.name(n), preds) : .direct(.name(n), preds)
        case .openBracket:
            // [ClassName] with no preceding name/wildcard — treat as wildcard + class predicate
            let preds = try parsePredicates()
            return recursive ? .recursive(.wildcard, preds) : .direct(.wildcard, preds)
        default:
            throw PathError.expectedName
        }
    }

    // Parse zero or more [predicate] blocks
    private mutating func parsePredicates() throws -> [Predicate] {
        var preds: [Predicate] = []
        while case .openBracket? = current {
            advance()
            let pred = try parsePredicate()
            preds.append(pred)
            guard case .closeBracket? = current else { throw PathError.expectedRBracket }
            advance()
        }
        return preds
    }

    private mutating func parsePredicate() throws -> Predicate {
        switch current {
        case .identifier(let fn) where fn == "contains":
            advance()
            guard case .openParen? = current else { throw PathError.expectedLParen }
            advance()
            guard case .at? = current else { throw PathError.expectedAt }
            advance()
            guard case .identifier(let attr)? = current else { throw PathError.expectedName }
            advance()
            guard case .comma? = current else { throw PathError.expectedComma }
            advance()
            let val = try parseStringVal()
            guard case .closeParen? = current else { throw PathError.expectedRParen }
            advance()
            switch attr {
            case "name":  return .nameContains(val)
            case "class": return .classContains(val)
            default:      throw PathError.invalidPredicate("contains() supports @name or @class")
            }

        case .at:
            advance()
            guard case .identifier(let attr)? = current else { throw PathError.expectedName }
            advance()
            switch attr {
            case "class":
                guard case .equals? = current else {
                    throw PathError.invalidPredicate("@class requires =")
                }
                advance()
                return .classEquals(try parseStringVal())
            case "id":
                guard case .equals? = current else {
                    throw PathError.invalidPredicate("@id requires =")
                }
                advance()
                if case .hexNumber(let v)? = current { advance(); return .idEquals(v) }
                if case .identifier(let s)? = current,
                   s.lowercased().hasPrefix("0x"),
                   let v = UInt64(s.dropFirst(2), radix: 16) {
                    advance(); return .idEquals(v)
                }
                throw PathError.invalidPredicate("@id value must be a hex number, e.g. 0x100000300")
            default:
                if case .equals? = current {
                    advance()
                    return .propertyEquals(attr, try parseStringVal())
                }
                return .propertyExists(attr)
            }

        case .identifier(let s):
            advance()
            if let n = Int(s), n >= 1 { return .position(n) }
            // [ClassName] shorthand — bare name in brackets means class match
            return .classEquals(s)

        default:
            throw PathError.invalidPredicate("expected @attr, contains(), or a class name")
        }
    }

    private mutating func parseStringVal() throws -> String {
        switch current {
        case .quotedString(let s): advance(); return s
        case .identifier(let s):   advance(); return s
        default: throw PathError.expectedStringValue
        }
    }
}
