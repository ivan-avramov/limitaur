import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityBPolicyTests {
    // New behaviour B1: exact public bounds and initial state, not inferred limits.
    @Test func defaultsAndConstants() {
        let p = PollingPolicy()
        #expect(PollingPolicy.floor == 30); #expect(PollingPolicy.ceiling == 120)
        #expect(PollingPolicy.step == 10); #expect(PollingPolicy.probeWait == 86_400)
        #expect(PollingPolicy.cleanRequired == 5); #expect(PollingPolicy.revertWindow == 3_600)
        #expect(PollingPolicy.blockDuration == 604_800)
        #expect(p.interval == 50); #expect(p.consecutiveClean == 0)
        #expect(p.lastChange == nil); #expect(p.lastReduction == nil); #expect(p.blockedUntil.isEmpty)
    }

    // New behaviour B4: upward rounding, invalid delays and saturation are independent.
    @Test(arguments: Array(0..<12)) func throttleTable(_ variant: Int) {
        let delays: [Double?] = [nil, 95, 400, 60, 60.001, 0, -1, .nan, .infinity, -.infinity, 1e308, 120]
        let expected: [Double] = [60, 100, 120, 60, 70, 60, 60, 60, 60, 60, 120, 120]
        var p = PollingPolicy(); bPrime(&p)
        let mutation22 = p.recordThrottle(now: bDate(10), retryAfter: delays[variant]); #expect(mutation22)
        #expect(p.interval == expected[variant]); #expect(p.consecutiveClean == 0)
        #expect(p.lastChange == bDate(10))
    }

    // Invariant B1: a ceiling hit still resets clean streak and timestamps the signal.
    @Test func ceilingThrottleReturnsFalseButUpdatesState() throws {
        var p = try bPolicy(120); bPrime(&p)
        let mutation30 = p.recordThrottle(now: bDate(12), retryAfter: nil); #expect(!mutation30)
        #expect(p.interval == 120); #expect(p.consecutiveClean == 0); #expect(p.lastChange == bDate(12))
    }

    // New behaviour B4: both the five-poll count and exact 24 h equality are necessary.
    @Test func cleanCountAndDayBoundary() throws {
        var early = try bPolicy(change: 0)
        for _ in 0..<5 { let mutation37 = early.recordClean(now: bDate(86_399.999), reductionAllowed: true); #expect(!mutation37) }
        #expect(early.interval == 50); #expect(early.consecutiveClean == 5)
        let mutation39 = early.recordClean(now: bDate(86_400), reductionAllowed: true); #expect(mutation39)
        #expect(early.interval == 40); #expect(early.consecutiveClean == 0)
        var late = try bPolicy(change: 0)
        for _ in 0..<4 { let mutation42 = late.recordClean(now: bDate(86_400), reductionAllowed: true); #expect(!mutation42) }
        #expect(late.interval == 50)
        let mutation44 = late.recordClean(now: bDate(86_400), reductionAllowed: true); #expect(mutation44)
        #expect(late.lastReduction?.from == 50); #expect(late.lastReduction?.to == 40)
        #expect(late.lastReduction?.at == bDate(86_400)); #expect(late.lastChange == bDate(86_400))
    }

    // New behaviour B1: a nil change date starts the probe clock, not an immediate probe.
    @Test func firstCleanStartsClockAndBlockedReductionPreservesSaturatedStreak() throws {
        var p = PollingPolicy()
        bPrime(&p, count: 20, at: 100)
        #expect(p.lastChange == bDate(100)); #expect(p.consecutiveClean == 5)
        let mutation54 = p.recordClean(now: bDate(86_499.999), reductionAllowed: true); #expect(!mutation54)
        let mutation55 = p.recordClean(now: bDate(86_500), reductionAllowed: false); #expect(!mutation55)
        #expect(p.consecutiveClean == 5); #expect(p.interval == 50)
        let mutation57 = p.recordClean(now: bDate(86_500), reductionAllowed: true); #expect(mutation57); #expect(p.interval == 40)
    }

    // New behaviour B4: counters saturate and never dirty persisted policy bytes.
    @Test func twentyCleanPollsSaturateWithoutPersistenceChurn() throws {
        var p = try bPolicy(change: 0)
        let before = try bEncoding(p)
        for _ in 0..<20 { let mutation64 = p.recordClean(now: bDate(1), reductionAllowed: true); #expect(!mutation64) }
        #expect(p.consecutiveClean == 5); #expect(try bEncoding(p) == before)
        let object = try #require(JSONSerialization.jsonObject(with: bEncoding(p)) as? [String: Any])
        #expect(object["consecutiveClean"] == nil)
    }

    // Invariant B1/B4: failure breaks a streak without moving any durable policy state.
    @Test func otherBreaksStreakWithoutMovingChangeDate() throws {
        var p = try bPolicy(change: -86_400); bPrime(&p)
        let before = try bEncoding(p); p.recordOther()
        #expect(p.consecutiveClean == 0); #expect(try bEncoding(p) == before)
        let mutation75 = p.recordClean(now: bDate(0), reductionAllowed: true); #expect(!mutation75); #expect(p.consecutiveClean == 1)
    }

    // Invariant B1: the floor is inclusive and cannot be crossed after a long idle period.
    @Test func floorNeverReduces() throws {
        var p = try bPolicy(30, change: -86_400); bPrime(&p)
        let mutation81 = p.recordClean(now: bDate(0), reductionAllowed: true); #expect(!mutation81)
        #expect(p.interval == 30); #expect(p.consecutiveClean == 5)
    }

    // New behaviour B4: revert is half-open, disallows negative elapsed time, and blocks the failed level.
    @Test(arguments: Array(0..<6)) func revertWindowAndRetryAfter(_ variant: Int) throws {
        let ages: [Double] = [-0.001, 0, 1_800, 3_599.999, 3_600, 5_400]
        var p = try bReduced()
        let age = ages[variant], reverts = age >= 0 && age < 3_600
        let mutation90 = p.recordThrottle(now: bDate(age), retryAfter: variant == 2 ? 95 : nil); #expect(mutation90)
        #expect(p.interval == (variant == 2 ? 100 : 50))
        #expect(p.blockedUntil[40] == (reverts ? bDate(age + 604_800) : nil))
        if reverts { #expect(p.lastReduction == nil) }
        #expect(p.lastChange == bDate(age)); #expect(p.consecutiveClean == 0)
    }

    // New behaviour B1/B4: the block's equality boundary expires before probing.
    @Test func sevenDayBlockExpiresAtEquality() throws {
        var p = try bReduced()
        _ = p.recordThrottle(now: bDate(1_800), retryAfter: nil)
        bPrime(&p, at: 86_400 + 1_800)
        let mutation102 = p.recordClean(now: bDate(606_599.999), reductionAllowed: true); #expect(!mutation102)
        #expect(p.interval == 50); #expect(p.blockedUntil[40] != nil)
        let mutation104 = p.recordClean(now: bDate(606_600), reductionAllowed: true); #expect(mutation104)
        #expect(p.interval == 40); #expect(p.blockedUntil[40] == nil)
    }

    // New behaviour B4: a backward wall jump resets the probe epoch and streak.
    @Test func backwardClockRestartsProbeWait() throws {
        var p = try bPolicy(change: 3_600, now: 3_600); bPrime(&p, at: 3_600)
        let mutation111 = p.recordClean(now: bDate(0), reductionAllowed: true); #expect(!mutation111)
        #expect(p.lastChange == bDate(0)); #expect(p.consecutiveClean == 0)
        bPrime(&p, at: 86_399.999)
        let mutation114 = p.recordClean(now: bDate(86_399.999), reductionAllowed: true); #expect(!mutation114)
        let mutation115 = p.recordClean(now: bDate(86_400), reductionAllowed: true); #expect(mutation115)
    }

    // Invariant B1: malformed or structurally invalid persisted state is rejected as a whole.
    @Test(arguments: Array(0..<15)) func decodeRejectsStructuralFailures(_ variant: Int) throws {
        var doc = BPolicyDocument(interval: 80, lastChange: bDate(-100))
        switch variant {
        case 0: doc.interval = 47
        case 1: doc.interval = 1e308
        case 2: doc.interval = -10
        case 3: doc.interval = 20
        case 4: doc.interval = 130
        case 5: doc.lastReduction = BReduction(from: 80, to: 60, at: bDate(-1))
        case 6: doc.lastReduction = BReduction(from: 47, to: 37, at: bDate(-1))
        case 7: doc.lastReduction = BReduction(from: 40, to: 20, at: bDate(-1))
        case 8: doc.blockedUntil = [25: bDate(100)]
        case 9: doc.blockedUntil = [130: bDate(100)]
        case 10: doc.blockedUntil = [0: bDate(-1)] // invalid key remains structural even if expired
        default: break
        }
        let data: Data
        switch variant {
        case 11: data = Data("{broken".utf8)
        case 12: data = Data("[]".utf8)
        case 13: data = Data("{\"interval\":\"50\",\"blockedUntil\":{}}".utf8)
        case 14: data = Data("null".utf8)
        default: data = try JSONEncoder().encode(doc)
        }
        #expect(PollingPolicy.decode(data, now: bDate(0)) == PollingPolicy())
    }

    // New behaviour B1: dates clamp individually; they do not invalidate valid structure.
    @Test func decodeClampsFutureDatesAndDropsExpiredBlocks() throws {
        let p = try bPolicy(80, change: 172_800,
            reduction: BReduction(from: 90, to: 80, at: bDate(100)),
            blocks: [30: bDate(-1), 40: bDate(0), 50: bDate(691_200), 60: bDate(10)])
        #expect(p.interval == 80); #expect(p.lastChange == bDate(0))
        #expect(p.lastReduction?.at == bDate(0)); #expect(p.lastReduction?.from == 90)
        #expect(p.blockedUntil == [50: bDate(604_800), 60: bDate(10)])
        #expect(p.consecutiveClean == 0)
    }

    // Invariant B1: valid Codable round-trip preserves everything except transient streak.
    @Test func roundTripExcludesOnlyCleanCounter() throws {
        var p = try bPolicy(80, change: -100,
            reduction: BReduction(from: 90, to: 80, at: bDate(-100)), blocks: [40: bDate(100)])
        bPrime(&p)
        let decoded = PollingPolicy.decode(try bEncoding(p), now: bDate(0))
        p.recordOther(); #expect(decoded == p); #expect(decoded.consecutiveClean == 0)
    }

    // Invariant B1: an injected persisted counter cannot buy the first post-launch probe.
    @Test func decodeIgnoresInjectedCleanCounter() throws {
        let wire = try JSONEncoder().encode(BPolicyDocument(interval: 80, lastChange: bDate(-86_400)))
        var object = try #require(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        object["consecutiveClean"] = Int.max
        var p = PollingPolicy.decode(try JSONSerialization.data(withJSONObject: object), now: bDate(0))
        #expect(p.interval == 80); #expect(p.consecutiveClean == 0)
        let mutation173 = p.recordClean(now: bDate(0), reductionAllowed: true); #expect(!mutation173)
        #expect(p.interval == 80); #expect(p.consecutiveClean == 1)
    }
}
