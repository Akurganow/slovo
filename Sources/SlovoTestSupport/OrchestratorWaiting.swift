import SlovoCore

/// Round-trips the caller's actor and the orchestrator until work already queued on
/// either has run. A test uses it to prove an effect absent, since absence is only
/// observable by waiting for it. A test also uses it to let a fire-and-forget push
/// land when the orchestrator exposes no state to wait on.
nonisolated(nonsending) public func settle(_ orchestrator: Orchestrator, rounds: Int = 200) async {
    for _ in 0..<rounds {
        await Task.yield()
        _ = await orchestrator.currentState()
    }
}

/// Polls until the condition holds, relenting at the bound so a broken implementation
/// fails its assertion instead of hanging the suite.
nonisolated(nonsending) public func waitUntil(rounds: Int = 500, _ condition: () async -> Bool) async -> Bool {
    for _ in 0..<rounds {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}
