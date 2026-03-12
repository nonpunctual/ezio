// Shell.swift — Interactive REPL mode (like dscl / scutil)
import Foundation

// MARK: - State

private enum ShellLevel {
    case registry
    case plane(name: String, root: IORegNode, stack: [IORegNode])
}

private struct ShellState {
    var level: ShellLevel = .registry

    var currentPath: String {
        switch level {
        case .registry:
            return "IORegistry"
        case .plane(let name, _, let stack):
            return ([name] + stack.map { $0.name }).joined(separator: "/")
        }
    }

    var prompt: String { "\(currentPath)> " }

    var currentNode: IORegNode? {
        switch level {
        case .registry:                          return nil
        case .plane(_, let root, let stack):     return stack.last ?? root
        }
    }
}

// MARK: - Entry point

func runInteractive(planeLoader: (String) throws -> IORegNode) {
    var state = ShellState()
    print("ezio interactive  type 'help' for commands, ctrl-d or 'quit' to exit.\n")

    outerLoop: while true {
        print(state.prompt, terminator: "")
        fflush(stdout)

        guard let line = readLine(strippingNewline: true) else {
            print("")
            break
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd   = parts[0].lowercased()
        let arg   = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil

        switch cmd {

        case "ls":
            switch state.level {
            case .registry:
                for (i, p) in planeOrder.enumerated() {
                    print(String(format: "  %3d  %@", i + 1, p))
                }
            case .plane(_, let root, let stack):
                cmdLS(stack.last ?? root)
            }

        case "cd":
            let target = arg ?? "/"
            cmdCD(target, state: &state, planeLoader: planeLoader)

        case "pwd":
            print(state.currentPath)

        case "info":
            guard let node = state.currentNode else { print("  (at IORegistry root)"); continue }
            cmdInfo(node)

        case "read":
            guard let node = state.currentNode else { print("  (at IORegistry root — cd into a plane first)"); continue }
            cmdRead(node)

        case "get":
            guard let node = state.currentNode else { print("  (at IORegistry root — cd into a plane first)"); continue }
            guard let key = arg else { print("usage: get <key>"); continue }
            cmdGet(key, node: node)

        case "keys":
            guard let node = state.currentNode else { print("  (at IORegistry root — cd into a plane first)"); continue }
            let keys = node.properties.keys.sorted()
            if keys.isEmpty { print("  (no properties)") }
            else { keys.forEach { print("  \($0)") } }

        case "find":
            guard let term = arg else { print("usage: find <term>"); continue }
            switch state.level {
            case .registry:
                print("  (cd into a plane first)")
            case .plane(let name, let root, let stack):
                cmdFind(term, node: stack.last ?? root, plane: name, breadcrumb: stack.map { $0.name })
            }

        case "help", "?":
            printHelp()

        case "quit", "exit", "q":
            break outerLoop

        default:
            print("unknown command '\(cmd)' — type 'help' for commands")
        }
    }
}

// MARK: - Navigation

private func cmdCD(_ target: String, state: inout ShellState, planeLoader: (String) throws -> IORegNode) {
    // Go to absolute root
    if target == "/" || target == "~" {
        state.level = .registry
        return
    }

    switch state.level {
    case .registry:
        // At IORegistry root — target must be a plane name or index
        let planeName: String?
        if let i = Int(target), i >= 1 && i <= planeOrder.count {
            planeName = planeOrder[i - 1]
        } else if knownPlanes.contains(target) {
            planeName = target
        } else if let match = planeOrder.first(where: { $0.lowercased().hasPrefix(target.lowercased()) }) {
            planeName = match
        } else {
            planeName = nil
        }
        guard let name = planeName else {
            print("unknown plane '\(target)' — type 'ls' to see planes")
            return
        }
        do {
            print("  loading \(name)…")
            let root = try planeLoader(name)
            state.level = .plane(name: name, root: root, stack: [])
        } catch {
            print("error: \(error)")
        }

    case .plane(let name, let root, var stack):
        if target == ".." || target == "../" {
            if stack.isEmpty {
                state.level = .registry
            } else {
                stack.removeLast()
                state.level = .plane(name: name, root: root, stack: stack)
            }
            return
        }
        let current = stack.last ?? root
        let children = current.children
        if let i = Int(target) {
            let idx = i - 1
            guard idx >= 0 && idx < children.count else {
                print("index \(i) out of range (1–\(children.count))")
                return
            }
            stack.append(children[idx])
            state.level = .plane(name: name, root: root, stack: stack)
            return
        }
        if let child = children.first(where: { $0.name == target }) {
            stack.append(child)
            state.level = .plane(name: name, root: root, stack: stack)
            return
        }
        if let child = children.first(where: { $0.name.lowercased().hasPrefix(target.lowercased()) }) {
            stack.append(child)
            state.level = .plane(name: name, root: root, stack: stack)
            return
        }
        print("no child named '\(target)'")
    }
}

// MARK: - Inspection

private func cmdLS(_ node: IORegNode) {
    if node.children.isEmpty { print("  (no children)"); return }
    for (i, child) in node.children.enumerated() {
        let childCount = child.children.isEmpty ? "" : "  (\(child.children.count) children)"
        let paddedName = child.name.padding(toLength: 40, withPad: " ", startingAt: 0)
        print(String(format: "  %3d  %@  <%@>%@",
            i + 1, paddedName, child.ioClass, childCount))
    }
}

private func cmdInfo(_ node: IORegNode) {
    print("  name:     \(node.name)")
    print("  class:    \(node.ioClass)")
    print("  id:       \(String(format: "0x%x", node.id))")
    print("  props:    \(node.properties.count)")
    print("  children: \(node.children.count)")
}

private func cmdRead(_ node: IORegNode) {
    let props = node.properties.sortedByKey()
    if props.isEmpty { print("  (no properties)"); return }
    for (key, value) in props {
        print("  \(key): \(formatValue(value, indent: 4))")
    }
}

private func cmdGet(_ key: String, node: IORegNode) {
    if let value = node.properties[key] {
        print(rawString(value)); return
    }
    if let match = node.properties.keys.first(where: { $0.lowercased() == key.lowercased() }),
       let value = node.properties[match] {
        print(rawString(value)); return
    }
    print("key '\(key)' not found")
}

private func cmdFind(_ term: String, node: IORegNode, plane: String, breadcrumb: [String]) {
    var found = 0
    func search(_ n: IORegNode, crumb: [String]) {
        let nameOrClass = n.name == term || n.ioClass == term
        let matchedKeys = n.properties.keys.filter { $0 == term }.sorted()
        if nameOrClass || !matchedKeys.isEmpty {
            let path = ([plane] + crumb).joined(separator: "/")
            print("  \(n.name) <\(n.ioClass)> [\(String(format: "0x%x", n.id))]")
            print("    \(path)")
            for key in matchedKeys {
                if let val = n.properties[key] { print("    \(key) = \(formatValue(val, indent: 6))") }
            }
            found += 1
        }
        for child in n.children { search(child, crumb: crumb + [child.name]) }
    }
    for child in node.children { search(child, crumb: breadcrumb + [child.name]) }
    if found == 0 { print("  no matches for '\(term)'") }
    else if found > 1 { print("  \(found) results") }
}

// MARK: - Help

private func printHelp() {
    print("""
      Navigation:
        ls                  list children (or planes at IORegistry root)
        cd <name|number>    enter child node or plane
        cd ..               go up one level (cd .. from plane root returns to IORegistry)
        cd /                return to IORegistry root
        pwd                 show current path

      Inspection:
        info                show current node identity
        read                show all properties
        keys                list property key names
        get <key>           show raw value of a property

      Search:
        find <term>         search from current node (name, class, or key)

      Other:
        help                this help
        quit                exit
    """)
}
