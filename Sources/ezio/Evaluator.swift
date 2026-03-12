// Evaluator.swift — Evaluate a PathExpr against the IORegistry node tree

enum EvalResult {
    case nodes([NodeContext])
    case propertyValues([(context: NodeContext, key: String, value: IORegValue)])
}

func evaluate(
    expr: PathExpr,
    planeLoader: (String) throws -> IORegNode
) throws -> EvalResult {
    let root = try planeLoader(expr.plane)
    let rootCtx = NodeContext(node: root, plane: expr.plane, breadcrumb: [root.name])

    // Implicit (bare name) search: discovery mode across name, class, and property keys
    if expr.isImplicitSearch, let term = expr.implicitTerm {
        var results: [NodeContext] = []
        collectImplicitMatches(of: root, plane: expr.plane, breadcrumb: [root.name], term: term, into: &results)
        return .nodes(results)
    }

    var contexts: [NodeContext] = [rootCtx]

    for step in expr.steps {
        contexts = applyStep(step, to: contexts)
    }

    if let propKey = expr.propertySelect {
        let results: [(context: NodeContext, key: String, value: IORegValue)] = contexts.compactMap {
            guard let val = $0.node.properties[propKey] else { return nil }
            return ($0, propKey, val)
        }
        return .propertyValues(results)
    }

    return .nodes(contexts)
}

// MARK: - Implicit (discovery) search

private func collectImplicitMatches(
    of node: IORegNode,
    plane: String,
    breadcrumb: [String],
    term: String,
    into results: inout [NodeContext]
) {
    for child in node.children {
        var childBreadcrumb = breadcrumb
        childBreadcrumb.append(child.name)
        let nameOrClassMatch = child.name == term || child.ioClass == term
        let matchedKeys: [String] = child.properties[term] != nil ? [term] : []

        if nameOrClassMatch || !matchedKeys.isEmpty {
            results.append(NodeContext(
                node: child,
                plane: plane,
                breadcrumb: childBreadcrumb,
                matchedPropertyKeys: matchedKeys
            ))
        }
        collectImplicitMatches(of: child, plane: plane, breadcrumb: childBreadcrumb, term: term, into: &results)
    }
}

// MARK: - Step application

private func applyStep(_ step: PathStep, to contexts: [NodeContext]) -> [NodeContext] {
    switch step {
    case .direct(let matcher, let predicates):
        var nonPos: [Predicate] = []
        var posIndex: Int?
        for p in predicates {
            if case .position(let n) = p { posIndex = n } else { nonPos.append(p) }
        }
        return contexts.flatMap { ctx -> [NodeContext] in
            var candidates = ctx.node.children
                .filter { nodeMatches($0, matcher: matcher, predicates: nonPos) }
                .map { NodeContext(node: $0, plane: ctx.plane, breadcrumb: ctx.breadcrumb + [$0.name]) }
            if let n = posIndex {
                candidates = (n >= 1 && n <= candidates.count) ? [candidates[n - 1]] : []
            }
            return candidates
        }
    case .recursive(let matcher, let predicates):
        return contexts.flatMap { ctx in
            var results: [NodeContext] = []
            collectDescendants(
                of: ctx.node,
                plane: ctx.plane,
                breadcrumb: ctx.breadcrumb,
                matcher: matcher,
                predicates: predicates,
                into: &results
            )
            return results
        }
    }
}

private func collectDescendants(
    of node: IORegNode,
    plane: String,
    breadcrumb: [String],
    matcher: NodeMatcher,
    predicates: [Predicate],
    into results: inout [NodeContext]
) {
    for child in node.children {
        var childBreadcrumb = breadcrumb
        childBreadcrumb.append(child.name)
        if nodeMatches(child, matcher: matcher, predicates: predicates) {
            results.append(NodeContext(node: child, plane: plane, breadcrumb: childBreadcrumb))
        }
        collectDescendants(of: child, plane: plane, breadcrumb: childBreadcrumb, matcher: matcher, predicates: predicates, into: &results)
    }
}

// MARK: - Matching

private func nodeMatches(_ node: IORegNode, matcher: NodeMatcher, predicates: [Predicate]) -> Bool {
    let nameMatch: Bool
    switch matcher {
    case .wildcard:       nameMatch = true
    case .name(let n):    nameMatch = node.name == n
    }
    guard nameMatch else { return false }
    return predicates.allSatisfy { satisfiesPredicate($0, node: node) }
}

private func satisfiesPredicate(_ pred: Predicate, node: IORegNode) -> Bool {
    switch pred {
    case .classEquals(let s):     return node.ioClass == s
    case .classContains(let s):   return node.ioClass.contains(s)
    case .idEquals(let v):        return node.id == v
    case .nameContains(let s):    return node.name.contains(s)
    case .propertyExists(let k):  return node.properties[k] != nil
    case .propertyEquals(let k, let v):
        guard let propVal = node.properties[k] else { return false }
        return simpleString(propVal) == v
    case .position:
        return true  // handled at step level, not per-node
    }
}

private func simpleString(_ val: IORegValue) -> String {
    switch val {
    case .bool(let b):   return b ? "true" : "false"
    case .int(let i):    return "\(i)"
    case .float(let f):  return "\(f)"
    case .string(let s): return s
    default:             return ""
    }
}
