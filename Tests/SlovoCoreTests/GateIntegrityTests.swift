import Foundation
import Testing

// Gate-integrity / no-op proof: a deliberately failing test must make the
// gate exit FAILURE, proving the gate is not a no-op.
//
// The probe is ARMED only when `SLOVO_GATE_SELFTEST=red`; default `swift test`
// leaves it disarmed (GREEN). The DEMONSTRATION is the evidence:
//   - `SLOVO_GATE_SELFTEST=red swift test` exits NON-ZERO and names this test;
//   - default `swift test` is GREEN.
//
// Stated sensitivity (the keystone false-green guard): if this probe could NOT
// turn the gate RED when armed (e.g. body `#expect(true)`, or a swallowed
// failure), it would itself be false-green and is rejected. The armed run is
// captured as run-evidence, not left permanently RED.
//
// NOTE: this probe is self-contained (env-gated assertion). The OTHER
// behavioral checks are RED today because the production API
// they assert against is absent — that is their intended RED reason.
@Suite("Gate integrity")
struct GateIntegrityTests {
    private static var isArmed: Bool {
        ProcessInfo.processInfo.environment["SLOVO_GATE_SELFTEST"] == "red"
    }

    /// Armed → fail loudly so the gate exits non-zero. Disarmed → assert the
    /// disarmed invariant so the test still runs a real (passing) assertion rather
    /// than being skipped (a skipped test proves nothing about the gate).
    @Test
    func gateGoesRedWhenSelfTestArmed() {
        if Self.isArmed {
            Issue.record("SLOVO_GATE_SELFTEST=red: gate-integrity probe ARMED — gate must fail")
        } else {
            #expect(Self.isArmed == false, "disarmed by default; arm via SLOVO_GATE_SELFTEST=red")
        }
    }
}
