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

    var contexts: [NodeContext] = [rootCtx]

    // Implicit (bare name) search: discovery mode across name, class, and property keys.
    // Folded in as an ordinary first pass so trailing predicates/steps/propertySelect
    // still apply to its results, instead of being silently discarded.
    if expr.isImplicitSearch, let term = expr.implicitTerm {
        let (nonPos, posIndex) = splitPosition(expr.implicitPredicates)
        contexts = contexts.flatMap { ctx -> [NodeContext] in
            var results: [NodeContext] = []
            collectDescendants(of: ctx.node, plane: ctx.plane, breadcrumb: ctx.breadcrumb, matcher: .implicit(term), predicates: nonPos, into: &results)
            if let n = posIndex {
                results = (n >= 1 && n <= results.count) ? [results[n - 1]] : []
            }
            return results
        }
    }

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

// MARK: - Step application

// Splits [n] position predicates out from boolean node-test predicates.
// Position selects the nth match by document order among a step's results
// and cannot be evaluated per-node, so it is applied after matching.
private func splitPosition(_ predicates: [Predicate]) -> (nonPosition: [Predicate], position: Int?) {
    var nonPos: [Predicate] = []
    var posIndex: Int?
    for p in predicates {
        if case .position(let n) = p { posIndex = n } else { nonPos.append(p) }
    }
    return (nonPos, posIndex)
}

private func applyStep(_ step: PathStep, to contexts: [NodeContext]) -> [NodeContext] {
    switch step {
    case .direct(let matcher, let predicates):
        let (nonPos, posIndex) = splitPosition(predicates)
        return contexts.flatMap { ctx -> [NodeContext] in
            var candidates: [NodeContext] = []
            for child in ctx.node.children {
                guard let keys = nodeMatches(child, matcher: matcher, predicates: nonPos) else { continue }
                candidates.append(NodeContext(node: child, plane: ctx.plane, breadcrumb: ctx.breadcrumb + [child.name], matchedPropertyKeys: keys))
            }
            if let n = posIndex {
                candidates = (n >= 1 && n <= candidates.count) ? [candidates[n - 1]] : []
            }
            return candidates
        }
    case .recursive(let matcher, let predicates):
        let (nonPos, posIndex) = splitPosition(predicates)
        return contexts.flatMap { ctx -> [NodeContext] in
            var results: [NodeContext] = []
            collectDescendants(of: ctx.node, plane: ctx.plane, breadcrumb: ctx.breadcrumb, matcher: matcher, predicates: nonPos, into: &results)
            if let n = posIndex {
                results = (n >= 1 && n <= results.count) ? [results[n - 1]] : []
            }
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
        let childBreadcrumb = breadcrumb + [child.name]
        if let keys = nodeMatches(child, matcher: matcher, predicates: predicates) {
            results.append(NodeContext(node: child, plane: plane, breadcrumb: childBreadcrumb, matchedPropertyKeys: keys))
        }
        collectDescendants(of: child, plane: plane, breadcrumb: childBreadcrumb, matcher: matcher, predicates: predicates, into: &results)
    }
}

// MARK: - Matching

// Returns the property keys that satisfied the match (possibly empty), or nil if no match.
private func nodeMatches(_ node: IORegNode, matcher: NodeMatcher, predicates: [Predicate]) -> [String]? {
    var matchedKeys: [String] = []
    switch matcher {
    case .wildcard:
        break
    case .name(let n):
        guard node.name == n else { return nil }
    case .implicit(let term):
        let (matched, keys) = discoveryMatch(node, term: term)
        guard matched else { return nil }
        matchedKeys += keys
    }
    for pred in predicates {
        guard let keys = satisfiesPredicate(pred, node: node) else { return nil }
        matchedKeys += keys
    }
    return matchedKeys
}

// Returns the property keys the predicate matched via (possibly empty), or nil if it failed.
private func satisfiesPredicate(_ pred: Predicate, node: IORegNode) -> [String]? {
    switch pred {
    case .classEquals(let s):     return node.ioClass == s ? [] : nil
    case .classContains(let s):   return node.ioClass.contains(s) ? [] : nil
    case .idEquals(let v):        return node.id == v ? [] : nil
    case .nameContains(let s):    return node.name.contains(s) ? [] : nil
    case .propertyExists(let k):  return node.properties[k] != nil ? [k] : nil
    case .propertyEquals(let k, let v):
        guard let propVal = node.properties[k], rawString(propVal) == v else { return nil }
        return [k]
    case .position:
        return []  // handled at step level via splitPosition, not per-node
    }
}
