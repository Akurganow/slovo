
/// Owns the fire-and-forget detection/recording task. `Task.detached` is
/// deliberate rather than incidental: it pins the work to `.utility` priority
/// (a plain `Task {}` would inherit the caller's), severs task-local and
/// priority inheritance from the dictation that spawned it, and keeps the
/// detector's Levenshtein pass independent of the caller's isolation — so
/// moving this call onto the Orchestrator actor could never drag the work onto
/// it. A `FallbackCleaner` pass-through arrives here with `cleaned == raw` and
/// yields zero events by construction.
enum TermMissReporter {
    static func spawn(
        raw: String,
        cleaned: String,
        vocabulary: [Term],
        recorder: any TermMissRecording,
        log: RedactionSafeLog
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            let detection = TermMissDetector.detectMisses(raw: raw, cleaned: cleaned, vocabulary: vocabulary)
            // Coarse counts only — never a key, surface, or transcript.
            log.event("termMisses detected=\(detection.missKeys.count)"
                + " unmatched=\(detection.unmatchedTermCount)"
                + " shortSkipped=\(detection.shortTermSkippedCount)")
            guard !detection.missKeys.isEmpty else { return }
            await recorder.recordMisses(detection.missKeys)
        }
    }
}
