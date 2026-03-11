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
        let results = collectImplicitMatches(
            of: root,
            plane: expr.plane,
            breadcrumb: [root.name],
            term: term
        )
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
    term: String
) -> [NodeContext] {
    var results: [NodeContext] = []
    for child in node.children {
        let childBreadcrumb = breadcrumb + [child.name]
        let nameOrClassMatch = child.name == term || child.ioClass == term
        let matchedKeys = child.properties.keys.filter { $0 == term }.sorted()

        if nameOrClassMatch || !matchedKeys.isEmpty {
            results.append(NodeContext(
                node: child,
                plane: plane,
                breadcrumb: childBreadcrumb,
                matchedPropertyKeys: matchedKeys
            ))
        }
        results += collectImplicitMatches(
            of: child,
            plane: plane,
            breadcrumb: childBreadcrumb,
            term: term
        )
    }
    return results
}

// MARK: - Step application

private func applyStep(_ step: PathStep, to contexts: [NodeContext]) -> [NodeContext] {
    switch step {
    case .direct(let matcher, let predicates):
        return contexts.flatMap { ctx in
            ctx.node.children
                .filter { nodeMatches($0, matcher: matcher, predicates: predicates) }
                .map { NodeContext(node: $0, plane: ctx.plane, breadcrumb: ctx.breadcrumb + [$0.name]) }
        }
    case .recursive(let matcher, let predicates):
        return contexts.flatMap { ctx in
            collectDescendants(
                of: ctx.node,
                plane: ctx.plane,
                breadcrumb: ctx.breadcrumb,
                matcher: matcher,
                predicates: predicates
            )
        }
    }
}

private func collectDescendants(
    of node: IORegNode,
    plane: String,
    breadcrumb: [String],
    matcher: NodeMatcher,
    predicates: [Predicate]
) -> [NodeContext] {
    var results: [NodeContext] = []
    for child in node.children {
        let childBreadcrumb = breadcrumb + [child.name]
        if nodeMatches(child, matcher: matcher, predicates: predicates) {
            results.append(NodeContext(node: child, plane: plane, breadcrumb: childBreadcrumb))
        }
        results += collectDescendants(
            of: child,
            plane: plane,
            breadcrumb: childBreadcrumb,
            matcher: matcher,
            predicates: predicates
        )
    }
    return results
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
