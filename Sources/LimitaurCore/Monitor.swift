import Foundation
import Darwin

public protocol MonitorClock: Sendable {
    func wallNow() -> Date
    func monotonicNow() -> TimeInterval
}
public struct SystemMonitorClock: MonitorClock {
    public init() {}
    public func wallNow() -> Date { Date() }
    public func monotonicNow() -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
}

enum DisplayWaitPolicy {
    // A single one-shot wait may be re-evaluated after this interval. The
    // provider's absolute expiry and every throttle deadline remain unchanged.
    static let maximumInterval: TimeInterval = 30 * 24 * 60 * 60

    static func interval(deadline: TimeInterval, now: TimeInterval) -> TimeInterval? {
        guard deadline.isFinite, now.isFinite, deadline > now else { return nil }
        let remaining = deadline - now
        guard !remaining.isNaN else { return nil }
        return min(max(0.001, remaining), maximumInterval)
    }
}

func absoluteDisplayDeadline(_ date: Date, wallNow: Date,
                             monotonicNow: TimeInterval) -> TimeInterval? {
    guard date > wallNow, monotonicNow.isFinite else { return nil }
    let remaining = date.timeIntervalSince(wallNow)
    guard remaining > 0, !remaining.isNaN else { return nil }
    let converted = monotonicNow + remaining
    if !converted.isFinite { return .greatestFiniteMagnitude }
    return max(converted, monotonicNow.nextUp)
}

public struct ProfileDisplay: Sendable {
    public let profile: AccountProfile
    public let snapshot: UsageSnapshot?
    public let health: Health
    public let message: String?
    public let fetchedAge: TimeInterval?
    public let freshnessDeadline: TimeInterval?
    public let snapshotGeneration: Int?
    public let expirations: SnapshotExpirations
    public init(profile: AccountProfile, snapshot: UsageSnapshot?, health: Health, message: String?, fetchedAge: TimeInterval?,
                freshnessDeadline: TimeInterval? = nil, snapshotGeneration: Int? = nil,
                expirations: SnapshotExpirations = SnapshotExpirations()) {
        self.profile = profile; self.snapshot = snapshot; self.health = health; self.message = message; self.fetchedAge = fetchedAge
        self.freshnessDeadline = freshnessDeadline; self.snapshotGeneration = snapshotGeneration
        self.expirations = expirations
    }
}

public struct SnapshotExpirations: Sendable, Equatable {
    public var metrics: Set<String> = []
    public var balances: Set<Int> = []
    public var credits: Set<Int> = []
    public init() {}
    public mutating func formUnion(_ other: Self) {
        metrics.formUnion(other.metrics); balances.formUnion(other.balances); credits.formUnion(other.credits)
    }
}

public struct PresentationCandidate: Sendable {
    public let metric: RankedMetric
    public let freshnessDeadline: TimeInterval?
    public let snapshotGeneration: Int?
    public init(metric: RankedMetric, freshnessDeadline: TimeInterval?, snapshotGeneration: Int?) {
        self.metric = metric; self.freshnessDeadline = freshnessDeadline; self.snapshotGeneration = snapshotGeneration
    }
}

public struct MonitorDisplay: Sendable {
    public let profiles: [ProfileDisplay]
    public let selected: [RankedMetric]
    public let candidates: [PresentationCandidate]
    public let revision: UInt64
    public let nextDisplayDeadline: TimeInterval?
    public init(profiles: [ProfileDisplay], candidates: [PresentationCandidate], revision: UInt64,
                nextDisplayDeadline: TimeInterval?) {
        let bounded = Array(candidates.prefix(8))
        self.profiles = profiles
        self.candidates = bounded
        self.selected = Array(bounded.prefix(3)).map(\.metric)
        self.revision = revision
        self.nextDisplayDeadline = nextDisplayDeadline
    }
    /// Compatibility for synthetic callers. These candidates have no clock proof and
    /// are deliberately unavailable to the live presentation projector.
    public init(profiles: [ProfileDisplay], selected: [RankedMetric], nextDisplayDeadline: TimeInterval?) {
        self.init(profiles: profiles, candidates: selected.prefix(8).map {
            PresentationCandidate(metric: $0, freshnessDeadline: nil, snapshotGeneration: nil)
        }, revision: 0, nextDisplayDeadline: nextDisplayDeadline)
    }
}

public struct PresentationState: Sendable {
    public let revision: UInt64
    public let count: Int
    public let profiles: [ProfileDisplay]
    public let selected: [RankedMetric]
    public let providerWarning: Bool
    /// Providers with at least one profile that is not healthy, in row order, unique.
    public let unavailableProviders: [ProviderID]
    public let accessibilitySummary: String
}

/// All visible state is derived from one wall/continuous-clock sample. The caller
/// retains observations immediately while the actor receives their local-only handoff.
public func projectDisplay(_ display: MonitorDisplay, count requestedCount: Int, wallNow: Date,
                           monotonicNow: TimeInterval,
                           observations: inout [Int: SnapshotExpirations]) -> PresentationState {
    let count = indicatorCount(requestedCount)
    let active = Set(display.profiles.compactMap(\.snapshotGeneration))
    observations = observations.filter { active.contains($0.key) }
    var rows: [ProfileDisplay] = []
    for row in display.profiles {
        var expired = row.expirations
        if let snapshot = row.snapshot, let generation = row.snapshotGeneration {
            expired.formUnion(observations[generation] ?? SnapshotExpirations())
            for metric in snapshot.metrics where metric.resetsAt.map({ wallNow >= $0 }) == true {
                expired.metrics.insert(metric.id)
            }
            for (index, balance) in snapshot.balances.enumerated() where balance.expiresAt.map({ wallNow >= $0 }) == true {
                expired.balances.insert(index)
            }
            for (index, credit) in (snapshot.resetCredits?.details ?? []).enumerated() where credit.expiresAt.map({ wallNow >= $0 }) == true {
                expired.credits.insert(index)
            }
            observations[generation] = expired
        }
        let stale = row.freshnessDeadline.map { monotonicNow >= $0 } ?? (row.snapshot != nil)
        let health: Health = stale && (row.health == .healthy || row.health == .partial) ? .stale : row.health
        var message = row.message
        if stale && !(message?.contains("Cached usage stale") ?? false) {
            message = [message, "Cached usage stale"].compactMap { $0 }.joined(separator: "; ")
        }
        let age = row.freshnessDeadline.map { max(0, monotonicNow - ($0 - 90)) } ?? row.fetchedAge
        rows.append(ProfileDisplay(profile: row.profile, snapshot: row.snapshot, health: health,
                                   message: message, fetchedAge: age,
                                   freshnessDeadline: row.freshnessDeadline,
                                   snapshotGeneration: row.snapshotGeneration, expirations: expired))
    }
    let selected = display.candidates.compactMap { candidate -> RankedMetric? in
        guard let deadline = candidate.freshnessDeadline, monotonicNow < deadline,
              let generation = candidate.snapshotGeneration,
              !((observations[generation] ?? SnapshotExpirations()).metrics.contains(candidate.metric.metric.id)),
              candidate.metric.metric.resetsAt.map({ wallNow < $0 }) ?? true else { return nil }
        return candidate.metric
    }.prefix(count)
    let chosen = Array(selected)
    let warning = rows.contains { $0.health != .healthy }
    var unavailable: [ProviderID] = []
    for row in rows where row.health != .healthy && !unavailable.contains(row.profile.providerID) {
        unavailable.append(row.profile.providerID)
    }
    var labels = chosen.map { row in
        let percent = row.metric.usedPercent.map { String(format: "%.2f percent", $0) } ?? "unknown"
        let reset = row.metric.resetsAt.flatMap(displayableResetDate).map {
            "reset " + DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)
        } ?? "reset unknown"
        return "\(row.providerID.rawValue), \(row.accountLabel), \(row.metric.label), \(percent), \(reset), fresh"
    }
    labels += Array(repeating: "unavailable slot", count: max(0, count - chosen.count))
    if rows.contains(where: { !$0.expirations.metrics.isEmpty }) { labels.append("cached quota reset due") }
    if rows.contains(where: { !$0.expirations.balances.isEmpty || !$0.expirations.credits.isEmpty }) {
        labels.append("cached credit or balance expired")
    }
    for row in rows where row.health != .healthy {
        labels.append("\(row.profile.providerID.rawValue), \(row.profile.label), \(row.health.rawValue)")
    }
    return PresentationState(revision: display.revision, count: count, profiles: rows,
                             selected: chosen, providerWarning: warning, unavailableProviders: unavailable,
                             accessibilitySummary: labels.joined(separator: "; "))
}

private actor LookupCapacity {
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Bool, Never>)] = []
    func acquire() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler(operation: {
            await self.enqueue(id)
        }, onCancel: {
            Task { await self.cancel(id) }
        })
    }
    private func enqueue(_ id: UUID) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            if Task<Never, Never>.isCancelled {
                continuation.resume(returning: false)
            } else if active < 8 {
                active += 1
                continuation.resume(returning: true)
            } else {
                waiting.append((id, continuation))
            }
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        let waiter = waiting.remove(at: index).1
        waiter.resume(returning: false)
    }
    func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            let waiter = waiting.removeFirst().1
            waiter.resume(returning: true)
        }
    }
}

private struct Binding: Sendable {
    var profile: AccountProfile
    var credential: Credential
    var entityKey: String
    var generation: Int
    var authPaused: Bool = false
    var message: String?
}
private struct Entity {
    var key: String
    var provider: ProviderID
    var selectedAccountID: AccountID?
    var subscribers: Set<String> = []
    var epoch = 0
    var task: Task<Void, Never>?
    var snapshot: UsageSnapshot?
    var snapshotGeneration: Int?
    var expirations = SnapshotExpirations()
    var successfulInstant: TimeInterval?
    var health: Health = .unavailable
    var message: String?
    var throttleUntil: TimeInterval = 0
    var retryDate: Date?
    var failures = 0
    var lastAttempt: TimeInterval = -.infinity
    var alternateUsed = false
}

/// Noncredential state for verifying that a presentation action leaves request
/// ownership, cached data, authentication and throttling untouched.
struct PresentationActionState: Equatable {
    let bindingGeneration: Int
    let entityEpoch: Int
    let snapshotGeneration: Int?
    let hasCachedSnapshot: Bool
    let hasInFlightRequest: Bool
    let authPaused: Bool
    let throttleUntil: TimeInterval
    let health: Health
}

public actor Monitor {
    private let clock: any MonitorClock
    private let credentials: CredentialStore
    private let transport: any HTTPTransport
    private let registry: ProviderRegistry
    private let lookupCapacity = LookupCapacity()
    private var bindings: [String: Binding] = [:]
    private var entities: [String: Entity] = [:]
    private var profileFailures: [String: (Health, String)] = [:]
    private var loading: [String: (Int, AccountProfile, Task<Void, Never>, Bool)] = [:]
    private var sleepRevalidation: [String: (AccountProfile, Bool)] = [:]
    private var loadGeneration = 0
    private var configuredProfiles: [String: AccountProfile] = [:]
    private var generation = 0
    private var snapshotGeneration = 0
    private var displayRevision: UInt64 = 0
    private var awake = true
    private var outcomeCounts: [String: [String: Int]] = [:]
    private var eligibilityCounts: [String: Int] = [:]
    private var wasEligible = false
    private var changeContinuations: [UUID: AsyncStream<MonitorDisplay>.Continuation] = [:]
    private var tickTask: Task<Void, Never>?
    private var crossedDeadlineQueued = false
    private let beforeDisplayArm: (@Sendable () -> Void)?
    public init(clock: any MonitorClock = SystemMonitorClock(), credentials: CredentialStore = CredentialStore(),
                transport: any HTTPTransport = NativeHTTPTransport(), registry: ProviderRegistry = ProviderRegistry(),
                beforeDisplayArm: (@Sendable () -> Void)? = nil) {
        self.clock = clock; self.credentials = credentials; self.transport = transport; self.registry = registry
        self.beforeDisplayArm = beforeDisplayArm
    }

    public func changes() -> AsyncStream<MonitorDisplay> {
        let id = UUID()
        var receiver: AsyncStream<MonitorDisplay>.Continuation?
        let stream = AsyncStream<MonitorDisplay>(bufferingPolicy: .bufferingNewest(1)) { receiver = $0 }
        guard let receiver else { return stream }
        changeContinuations[id] = receiver
        receiver.yield(display())
        receiver.onTermination = { @Sendable _ in Task { await self.removeContinuation(id) } }
        return stream
    }
    private func removeContinuation(_ id: UUID) { changeContinuations[id] = nil }
    private func publish() {
        updateEligibility(wall: clock.wallNow(), mono: clock.monotonicNow())
        let value = display()
        for continuation in changeContinuations.values { continuation.yield(value) }
        armTick(value.nextDisplayDeadline)
    }

    public func setProfiles(_ profiles: [AccountProfile]) async {
        let profiles = normalizedProfiles(profiles)
        let next = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        if next != configuredProfiles { eligibilityCounts["configurationChanges", default: 0] += 1 }
        for (id, old) in configuredProfiles {
            if let replacement = next[id], replacement.source != old.source {
                eligibilityCounts["sourceChanges", default: 0] += 1
            }
            if old.enabled && next[id]?.enabled != true {
                eligibilityCounts["profileDisables", default: 0] += 1
            }
        }
        configuredProfiles = next
        let newIDs = Set(profiles.filter(\.enabled).map(\.id))
        for id in Array(bindings.keys) where !newIDs.contains(id) { detach(id) }
        for id in Array(loading.keys) where !newIDs.contains(id) {
            loading[id]?.2.cancel()
            loading[id] = nil
        }
        sleepRevalidation = sleepRevalidation.filter { newIDs.contains($0.key) && next[$0.key] == $0.value.0 }
        profileFailures = profileFailures.filter { newIDs.contains($0.key) }
        for profile in profiles where profile.enabled {
            if var old = bindings[profile.id], old.profile.providerID == profile.providerID,
               old.profile.source == profile.source, old.profile.expectedAccountID == profile.expectedAccountID {
                old.profile = profile
                bindings[profile.id] = old
                continue
            }
            detach(profile.id)
            if let pending = loading[profile.id] {
                if pending.1 == profile { continue }
                pending.2.cancel()
                loading[profile.id] = nil
            }
            beginLoad(profile, interactive: false, clearPause: false)
        }
        publish()
        await refresh(force: true, minimumSuccessAge: 10)
    }

    private func beginLoad(_ profile: AccountProfile, interactive: Bool, clearPause: Bool) {
        guard awake else {
            sleepRevalidation[profile.id] = (profile, clearPause)
            return
        }
        guard sourceMatches(profile), registry.adapter(for: profile.providerID) != nil else {
            profileFailures[profile.id] = (.unavailable, "Credential source unavailable")
            return
        }
        loadGeneration += 1
        let epoch = loadGeneration
        let store = credentials
        let capacity = lookupCapacity
        let now = clock.wallNow()
        if var binding = bindings[profile.id] {
            if clearPause { generation += 1; binding.generation = generation }
            binding.authPaused = true
            binding.message = "Connecting account"
            bindings[profile.id] = binding
            profileFailures[profile.id] = nil
        } else {
            profileFailures[profile.id] = (.unavailable, "Connecting account")
        }
        let task = Task.detached { [weak self] in
            guard await capacity.acquire() else { return }
            guard !Task.isCancelled else { await capacity.release(); return }
            let result: Result<Credential, CredentialFailure> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: .success(try store.load(profile.source, now: now,
                                                                                interactive: interactive)))
                    } catch {
                        continuation.resume(returning: .failure((error as? CredentialFailure) ?? .unreadable))
                    }
                }
            }
            await capacity.release()
            guard !Task.isCancelled else { return }
            await self?.loaded(profile: profile, epoch: epoch, clearPause: clearPause, result: result)
        }
        loading[profile.id] = (epoch, profile, task, clearPause)
    }

    private func loaded(profile: AccountProfile, epoch: Int, clearPause: Bool,
                        result: Result<Credential, CredentialFailure>) async {
        guard loading[profile.id]?.0 == epoch, configuredProfiles[profile.id] == profile,
              profile.enabled else { return }
        loading[profile.id] = nil
        switch result {
        case .failure(let error):
            eligibilityCounts["credentialFailures", default: 0] += 1
            if var binding = bindings[profile.id] {
                binding.authPaused = true
                binding.message = credentialMessage(error)
                bindings[profile.id] = binding
            } else {
                profileFailures[profile.id] = (.unauthenticated, credentialMessage(error))
            }
        case .success(let credential):
            if let expected = profile.expectedAccountID, credential.selectedAccountID != expected {
                detach(profile.id)
                profileFailures[profile.id] = (.unauthenticated, credentialMessage(CredentialFailure.accountMismatch))
                break
            }
            if let prior = bindings[profile.id], prior.credential.fingerprint == credential.fingerprint,
               prior.credential.selectedAccountID == credential.selectedAccountID {
                var binding = prior
                if clearPause { binding.authPaused = false; binding.message = nil }
                bindings[profile.id] = binding
            } else {
                let oldThrottle = bindings[profile.id].flatMap { previous in
                    previous.profile.source == profile.source ? entities[previous.entityKey]?.throttleUntil : nil
                } ?? 0
                detach(profile.id)
                generation += 1
                let selector = credential.selectedAccountID?.rawValue ?? "source:" + profile.source.stableID
                let initialKey = profile.providerID.rawValue + "|" + credential.fingerprint + "|" + selector
                let key = bindings.values.first(where: {
                    $0.profile.providerID == profile.providerID &&
                    $0.credential.fingerprint == credential.fingerprint &&
                    $0.credential.selectedAccountID == credential.selectedAccountID &&
                    entities[$0.entityKey] != nil
                })?.entityKey ?? initialKey
                pruneEntities()
                if entities[key] == nil && entities.count >= 256 {
                    bindings[profile.id] = nil
                    profileFailures[profile.id] = (.unavailable, "Account capacity reached; retry after throttles expire")
                    break
                }
                bindings[profile.id] = Binding(profile: profile, credential: credential, entityKey: key, generation: generation)
                if entities[key] == nil {
                    var entity = Entity(key: key, provider: profile.providerID,
                                        selectedAccountID: credential.selectedAccountID)
                    entity.throttleUntil = oldThrottle
                    if profile.providerID.rawValue == "codex", let selected = credential.selectedAccountID {
                        let verifiedKey = profile.providerID.rawValue + "|verified|" + selected.rawValue
                        entity.throttleUntil = max(entity.throttleUntil, entities.values.filter {
                            $0.provider == profile.providerID &&
                            ($0.selectedAccountID == selected || $0.key == verifiedKey)
                        }.map(\.throttleUntil).max() ?? 0)
                    }
                    entities[key] = entity
                }
                entities[key]?.subscribers.insert(profile.id)
            }
            profileFailures[profile.id] = nil
        }
        publish()
        if let key = bindings[profile.id]?.entityKey {
            await refreshEntities(force: true, minimumSuccessAge: clearPause ? nil : 10, onlyKey: key)
        }
    }

    private func detach(_ id: String) {
        guard let old = bindings.removeValue(forKey: id) else { return }
        guard var entity = entities[old.entityKey] else { return }
        entity.subscribers.remove(id)
        if entity.subscribers.isEmpty {
            entity.epoch += 1
            entity.task?.cancel(); entity.task = nil
            entity.snapshot = nil; entity.successfulInstant = nil
            entity.snapshotGeneration = nil; entity.expirations = SnapshotExpirations()
        }
        entities[old.entityKey] = entity
        pruneEntities()
    }

    private func pruneEntities() {
        let now = clock.monotonicNow()
        entities = entities.filter { !$0.value.subscribers.isEmpty || $0.value.throttleUntil > now }
        // Only active throttles remain detached; expired entries are purged at every transition.
    }

    public func reconnect(_ profileID: String) async {
        guard let profile = configuredProfiles[profileID], profile.enabled else { return }
        guard loading[profileID] == nil else { return }
        beginLoad(profile, interactive: profile.source == .claudeDefaultDiscovery, clearPause: true)
        publish()
    }

    public func manualRefresh() async {
        await refresh(force: true)
    }

    public func refresh(force: Bool = false, minimumSuccessAge: TimeInterval? = nil) async {
        await refreshEntities(force: force, minimumSuccessAge: minimumSuccessAge, onlyKey: nil)
    }

    private func refreshEntities(force: Bool, minimumSuccessAge: TimeInterval?, onlyKey: String?) async {
        guard awake else { return }
        pruneEntities()
        // Revalidate paused bindings only on explicit action; no periodic Keychain prompts.
        for key in entities.keys.sorted() {
            if let onlyKey, key != onlyKey { continue }
            guard var entity = entities[key], !entity.subscribers.isEmpty, entity.task == nil else { continue }
            let now = clock.monotonicNow()
            guard now >= entity.throttleUntil else { continue }
            if !force && now - entity.lastAttempt < 30 { continue }
            if let minimumSuccessAge, entity.successfulInstant.map({ now - $0 < minimumSuccessAge }) == true { continue }
            for id in entity.subscribers {
                if var binding = bindings[id], let expiry = binding.credential.expiresAt,
                   expiry <= clock.wallNow() {
                    if !binding.authPaused { eligibilityCounts["credentialExpiries", default: 0] += 1 }
                    binding.authPaused = true
                    binding.message = "Session expired; reconnect account"
                    bindings[id] = binding
                }
            }
            guard let id = entity.subscribers.sorted(by: { a, b in
                let x = bindings[a]?.profile.source.stableID ?? a
                let y = bindings[b]?.profile.source.stableID ?? b
                return x == y ? a < b : x < y
            }).first(where: { bindings[$0]?.authPaused == false }),
                let binding = bindings[id] else { continue }
            entity.epoch += 1
            let epoch = entity.epoch
            entity.lastAttempt = now
            entity.alternateUsed = false
            let transport = self.transport
            let adapter = registry.adapter(for: entity.provider)!
            entity.task = Task {
                let result: Result<HTTPResponse, Error>
                do { result = .success(try await adapter.request(credential: binding.credential, transport: transport)) }
                catch { result = .failure(error) }
                await self.complete(key: key, epoch: epoch, bindingID: id, bindingGeneration: binding.generation,
                                    sourceID: binding.profile.source.stableID, fingerprint: binding.credential.fingerprint,
                                    result: result)
            }
            entities[key] = entity
        }
        publish()
    }

    private func complete(key: String, epoch: Int, bindingID: String, bindingGeneration: Int,
                          sourceID: String, fingerprint: String,
                          result: Result<HTTPResponse, Error>) async {
        guard var entity = entities[key], entity.epoch == epoch, entity.task != nil else { return }
        entity.task = nil
        let subscriber = entity.subscribers.sorted().first { id in
            guard let candidate = bindings[id] else { return false }
            return !candidate.authPaused && candidate.entityKey == key && candidate.profile.source.stableID == sourceID &&
                   candidate.credential.fingerprint == fingerprint &&
                   (id != bindingID || candidate.generation == bindingGeneration)
        }
        guard let subscriber, let binding = bindings[subscriber] else {
            entities[key] = entity
            publish()
            await refresh(force: true)
            return
        }
        let mono = clock.monotonicNow(), wall = clock.wallNow()
        switch result {
        case .failure:
            count(entity.provider, "failed")
            entity.health = .failed; entity.message = "Connection unavailable"
            backoff(&entity, now: mono)
        case .success(let response):
            switch response.status {
            case 200:
                do {
                    let account = binding.credential.selectedAccountID ?? AccountID("source:" + binding.profile.source.stableID)
                    let snapshot = try UsageDecoder.decode(provider: entity.provider, data: response.body,
                                                           accountID: account, accountLabel: binding.profile.label, now: wall)
                    if let verified = verifiedAccount(response.body) {
                        if let expected = binding.profile.expectedAccountID, verified != expected {
                            throw CredentialFailure.accountMismatch
                        }
                        if entity.provider.rawValue == "codex", let selected = binding.credential.selectedAccountID,
                           verified != selected { throw CredentialFailure.accountMismatch }
                    }
                    entity.snapshot = snapshot; entity.successfulInstant = mono
                    snapshotGeneration += 1
                    entity.snapshotGeneration = snapshotGeneration
                    entity.expirations = SnapshotExpirations()
                    count(entity.provider, snapshot.partial ? "partial" : "success")
                    entity.health = snapshot.partial ? .partial : .healthy
                    entity.message = snapshot.partial ? "Incomplete provider data" : nil
                    entity.failures = 0; entity.throttleUntil = 0; entity.retryDate = nil
                    entities[key] = entity
                    if let verified = verifiedAccount(response.body) { merge(key: key, verified: verified) }
                    publish(); return
                } catch CredentialFailure.accountMismatch {
                    count(entity.provider, "unauthenticated")
                    for id in Array(entity.subscribers) {
                        guard let candidate = bindings[id], candidate.profile.source.stableID == sourceID,
                              candidate.credential.fingerprint == fingerprint else { continue }
                        bindings[id] = nil
                        entity.subscribers.remove(id)
                        profileFailures[id] = (.unauthenticated, "Configured account does not match session")
                    }
                    entity.health = .unauthenticated
                    entity.message = "Configured account does not match session"
                    if entity.subscribers.isEmpty {
                        entity.epoch += 1
                        entity.snapshot = nil
                        entity.successfulInstant = nil
                        entity.snapshotGeneration = nil
                        entity.expirations = SnapshotExpirations()
                    }
                } catch {
                    count(entity.provider, "failed")
                    entity.health = .failed; entity.message = "Provider response unavailable"
                    backoff(&entity, now: mono)
                }
            case 401, 403:
                count(entity.provider, "unauthenticated")
                for id in entity.subscribers {
                    guard var candidate = bindings[id], candidate.profile.source.stableID == sourceID,
                          candidate.credential.fingerprint == fingerprint, !candidate.authPaused else { continue }
                    candidate.authPaused = true; candidate.message = "Reconnect account"
                    bindings[id] = candidate
                }
                entity.health = .unauthenticated; entity.message = "Authentication required"
                if !entity.alternateUsed,
                   let alternate = entity.subscribers.sorted(by: { a, b in
                       let x = bindings[a]?.profile.source.stableID ?? a
                       let y = bindings[b]?.profile.source.stableID ?? b
                       return x == y ? a < b : x < y
                   }).first(where: { bindings[$0]?.authPaused == false }),
                   let other = bindings[alternate], mono >= entity.throttleUntil {
                    entity.alternateUsed = true
                    entity.epoch += 1
                    let nextEpoch = entity.epoch
                    let transport = self.transport
                    let adapter = registry.adapter(for: entity.provider)!
                    entity.task = Task {
                        let retry: Result<HTTPResponse, Error>
                        do { retry = .success(try await adapter.request(credential: other.credential, transport: transport)) }
                        catch { retry = .failure(error) }
                        await self.complete(key: key, epoch: nextEpoch, bindingID: alternate,
                                            bindingGeneration: other.generation,
                                            sourceID: other.profile.source.stableID,
                                            fingerprint: other.credential.fingerprint, result: retry)
                    }
                }
            case 429:
                count(entity.provider, "throttled")
                entity.health = .throttled; entity.message = "Provider throttled"
                backoff(&entity, now: mono)
                if let value = response.headers["retry-after"], let delay = retryDelay(value, wall: wall) {
                    entity.throttleUntil = max(entity.throttleUntil, mono + delay)
                }
                entity.retryDate = wall.addingTimeInterval(max(0, entity.throttleUntil - mono))
            default:
                count(entity.provider, "unavailable")
                entity.health = .unavailable; entity.message = "Provider unavailable"
                backoff(&entity, now: mono)
            }
        }
        entities[key] = entity
        publish()
    }
    private func count(_ provider: ProviderID, _ outcome: String) {
        outcomeCounts[provider.rawValue, default: [:]][outcome, default: 0] += 1
    }
    public func statistics() -> [String: [String: Int]] {
        var result = outcomeCounts
        let wall = clock.wallNow(), mono = clock.monotonicNow()
        updateEligibility(wall: wall, mono: mono)
        var status = eligibilityCounts
        let eligible = defaultWorkloadEligible(wall: wall, mono: mono)
        status["eligible"] = eligible ? 1 : 0
        status["processID"] = Int(getpid())
        status["observedAtContinuousNanoseconds"] = Int(mono * 1_000_000_000)
        status["validUntilContinuousNanoseconds"] = 0
        status["validUntilWallMilliseconds"] = 0
        if eligible {
            var deadline = TimeInterval.infinity
            var wallExpiry: Date?
            for id in ["codex-default", "claude-default"] {
                guard let binding = bindings[id], let entity = entities[binding.entityKey],
                      let success = entity.successfulInstant else { continue }
                deadline = min(deadline, success + 90)
                if let expiry = binding.credential.expiresAt {
                    deadline = min(deadline, mono + expiry.timeIntervalSince(wall))
                    wallExpiry = min(wallExpiry ?? expiry, expiry)
                }
            }
            if deadline.isFinite {
                status["validUntilContinuousNanoseconds"] = Int(deadline * 1_000_000_000)
            }
            if let wallExpiry {
                status["validUntilWallMilliseconds"] = Int(wallExpiry.timeIntervalSince1970 * 1000)
            }
        }
        result["__eligibility"] = status
        return result
    }
    private func defaultWorkloadEligible(wall: Date, mono: TimeInterval) -> Bool {
        guard awake, configuredProfiles.count == 2,
              let codex = configuredProfiles["codex-default"],
              let claude = configuredProfiles["claude-default"],
              codex.enabled, claude.enabled,
              codex.providerID == "codex", claude.providerID == "claude",
              codex.source == .codexFile(CredentialStore.defaultCodexPath),
              claude.source == .claudeDefaultDiscovery,
              loading["codex-default"] == nil, loading["claude-default"] == nil else { return false }
        for id in ["codex-default", "claude-default"] {
            guard let binding = bindings[id], !binding.authPaused,
                  let entity = entities[binding.entityKey], entity.subscribers.contains(id),
                  entity.health == .healthy, entity.snapshot != nil,
                  let success = entity.successfulInstant, mono < success + 90,
                  entity.throttleUntil <= mono,
                  binding.credential.expiresAt.map({ $0 > wall }) ?? true else { return false }
        }
        return true
    }
    private func updateEligibility(wall: Date, mono: TimeInterval) {
        let eligible = defaultWorkloadEligible(wall: wall, mono: mono)
        if wasEligible && !eligible { eligibilityCounts["violations", default: 0] += 1 }
        wasEligible = eligible
    }
    func retainedEntityCount() -> Int { entities.count }
    func isAttached(_ profileID: String) -> Bool {
        guard let binding = bindings[profileID], let entity = entities[binding.entityKey] else { return false }
        return !binding.authPaused && entity.subscribers.contains(profileID)
    }
    func throttleDeadline(for profileID: String) -> TimeInterval? {
        guard let binding = bindings[profileID] else { return nil }
        return entities[binding.entityKey]?.throttleUntil
    }
    func presentationActionState(for profileID: String) -> PresentationActionState? {
        guard let binding = bindings[profileID], let entity = entities[binding.entityKey] else { return nil }
        return PresentationActionState(bindingGeneration: binding.generation, entityEpoch: entity.epoch,
                                       snapshotGeneration: entity.snapshotGeneration,
                                       hasCachedSnapshot: entity.snapshot != nil,
                                       hasInFlightRequest: entity.task != nil,
                                       authPaused: binding.authPaused, throttleUntil: entity.throttleUntil,
                                       health: entity.health)
    }

    private func backoff(_ entity: inout Entity, now: TimeInterval) {
        entity.retryDate = nil
        entity.failures += 1
        let delay = min(900.0, 30.0 * pow(2.0, Double(min(entity.failures - 1, 5))))
        entity.throttleUntil = max(entity.throttleUntil, now + delay)
    }
    private func retryDelay(_ value: String, wall: Date) -> TimeInterval? {
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = format.date(from: value) { return max(0, date.timeIntervalSince(wall)) }
        return nil
    }
    private func verifiedAccount(_ data: Data) -> AccountID? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (root["account_id"] ?? root["accountId"]) as? String, !id.isEmpty else { return nil }
        return AccountID(id)
    }
    private func merge(key: String, verified: AccountID) {
        guard var entity = entities[key] else { return }
        entity.snapshot?.accountID = verified
        entity.selectedAccountID = verified
        let target = entity.provider.rawValue + "|verified|" + verified.rawValue
        if target == key { return }
        if var existing = entities[target] {
            existing.task?.cancel()
            existing.task = nil
            existing.epoch += 1
            if entity.throttleUntil > existing.throttleUntil { existing.retryDate = entity.retryDate }
            existing.throttleUntil = max(existing.throttleUntil, entity.throttleUntil)
            existing.failures = max(existing.failures, entity.failures)
            if (entity.successfulInstant ?? -.infinity) > (existing.successfulInstant ?? -.infinity) {
                existing.snapshot = entity.snapshot; existing.successfulInstant = entity.successfulInstant
                existing.snapshotGeneration = entity.snapshotGeneration
                existing.expirations = entity.expirations
                existing.health = entity.health; existing.message = entity.message
            }
            existing.subscribers.formUnion(entity.subscribers)
            entity.task?.cancel(); entity.epoch += 1
            entities[key] = nil; entities[target] = existing
        } else {
            entity.key = target; entities[key] = nil; entities[target] = entity
        }
        for id in entity.subscribers { bindings[id]?.entityKey = target }
    }

    public func sleep() {
        if awake { eligibilityCounts["sleepEvents", default: 0] += 1 }
        awake = false
        tickTask?.cancel(); tickTask = nil
        for (id, pending) in loading {
            sleepRevalidation[id] = (pending.1, pending.3)
            pending.2.cancel()
        }
        loading.removeAll()
        for key in entities.keys {
            entities[key]?.epoch += 1
            entities[key]?.task?.cancel()
            entities[key]?.task = nil
        }
        publish()
    }
    public func wake() async {
        awake = true
        let pending = sleepRevalidation
        sleepRevalidation.removeAll()
        for (id, entry) in pending where configuredProfiles[id] == entry.0 && entry.0.enabled {
            beginLoad(entry.0, interactive: false, clearPause: entry.1)
        }
        publish()
        await refresh(force: true)
    }
    public func clockChanged() {
        eligibilityCounts["clockChanges", default: 0] += 1
        publish()
    }
    public func dropdownOpened() async { await refresh(force: true, minimumSuccessAge: 10) }
    public func stop() {
        sleep()
        for key in entities.keys {
            entities[key]?.snapshot = nil
            entities[key]?.snapshotGeneration = nil
            entities[key]?.expirations = SnapshotExpirations()
        }
        for pending in loading.values { pending.2.cancel() }
        loading.removeAll()
        for continuation in changeContinuations.values { continuation.finish() }
        changeContinuations.removeAll()
    }
    @discardableResult public func settle() async -> Bool {
        // A completion can schedule a failover request, and a credential load can
        // attach another profile after an earlier request has completed. Observe
        // the actor's state until all work has actually finished.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if loading.isEmpty && entities.values.allSatisfy({ $0.task == nil }) {
                await Task.yield()
                if loading.isEmpty && entities.values.allSatisfy({ $0.task == nil }) { return true }
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }

    private func processExpirations(wall: Date) {
        for key in entities.keys {
            guard var entity = entities[key], let snapshot = entity.snapshot else { continue }
            for metric in snapshot.metrics where metric.resetsAt.map({ wall >= $0 }) == true {
                entity.expirations.metrics.insert(metric.id)
            }
            for (index, balance) in snapshot.balances.enumerated() where balance.expiresAt.map({ wall >= $0 }) == true {
                entity.expirations.balances.insert(index)
            }
            for (index, credit) in (snapshot.resetCredits?.details ?? []).enumerated() where credit.expiresAt.map({ wall >= $0 }) == true {
                entity.expirations.credits.insert(index)
            }
            entities[key] = entity
        }
    }

    public func observePresentationExpirations(_ seen: [Int: SnapshotExpirations]) {
        var changed = false
        for key in entities.keys {
            guard var entity = entities[key], let id = entity.snapshotGeneration,
                  let received = seen[id] else { continue }
            let previous = entity.expirations
            entity.expirations.formUnion(received)
            if entity.expirations != previous { changed = true }
            entities[key] = entity
        }
        if changed { publish() }
    }

    /// A local presentation query. It changes no fetch, binding, or throttle state.
    public func displayOnly() -> MonitorDisplay { display() }

    public func display() -> MonitorDisplay {
        let wall = clock.wallNow(), mono = clock.monotonicNow()
        processExpirations(wall: wall)
        displayRevision &+= 1
        var rows: [ProfileDisplay] = [], snapshots: [UsageSnapshot] = []
        var ages: [String: TimeInterval] = [:]
        var proof: [String: (TimeInterval, Int, SnapshotExpirations)] = [:]
        var next: TimeInterval?
        let orderedBindings = bindings.values.sorted { $0.profile.id < $1.profile.id }
        var primary: [String: Binding] = [:]
        for binding in orderedBindings {
            if primary[binding.entityKey] == nil || (primary[binding.entityKey]?.authPaused == true && !binding.authPaused) {
                primary[binding.entityKey] = binding
            }
        }
        for binding in orderedBindings {
            guard let entity = entities[binding.entityKey] else { continue }
            if !binding.authPaused, let expiry = binding.credential.expiresAt,
               let deadline = absoluteDisplayDeadline(expiry, wallNow: wall, monotonicNow: mono) {
                next = min(next ?? .infinity, deadline)
            }
            let age = entity.successfulInstant.map { max(0, mono - $0) }
            var health = binding.authPaused ? Health.unauthenticated : entity.health
            if let age, age >= 90, !binding.authPaused,
               (health == .healthy || health == .partial) { health = .stale }
            let retryLabel: String?
            if let retryDate = entity.retryDate {
                if let supported = displayableResetDate(retryDate) {
                    retryLabel = "Retry after " + DateFormatter.localizedString(from: supported, dateStyle: .short, timeStyle: .short)
                } else { retryLabel = "Retry time unavailable" }
            } else { retryLabel = nil }
            var statusMessage = binding.message ?? retryLabel ?? entity.message
            if let age, age >= 90 {
                statusMessage = [statusMessage, "Cached usage stale"].compactMap { $0 }.joined(separator: "; ")
            }
            if let owner = primary[binding.entityKey], owner.profile.id != binding.profile.id {
                let aliasMessage = "Alias of " + owner.profile.label + (statusMessage.map { "; " + $0 } ?? "")
                rows.append(ProfileDisplay(profile: binding.profile, snapshot: nil, health: health,
                                           message: aliasMessage, fetchedAge: age,
                                           freshnessDeadline: entity.successfulInstant.map { $0 + 90 },
                                           snapshotGeneration: entity.snapshotGeneration,
                                           expirations: entity.expirations))
                continue
            }
            if var snapshot = entity.snapshot {
                snapshot.accountLabel = binding.profile.label
                rows.append(ProfileDisplay(profile: binding.profile, snapshot: snapshot, health: health,
                                           message: statusMessage, fetchedAge: age,
                                           freshnessDeadline: entity.successfulInstant.map { $0 + 90 },
                                           snapshotGeneration: entity.snapshotGeneration,
                                           expirations: entity.expirations))
                var rankable = snapshot
                rankable.metrics.removeAll { entity.expirations.metrics.contains($0.id) }
                snapshots.append(rankable)
                let key = snapshot.providerID.rawValue + "\u{1f}" + snapshot.accountID.rawValue
                ages[key] = age
                if proof[key] == nil, let instant = entity.successfulInstant, let id = entity.snapshotGeneration {
                    proof[key] = (instant + 90, id, entity.expirations)
                }
                if let instant = entity.successfulInstant, mono < instant + 90 {
                    next = min(next ?? .infinity, instant + 90)
                    for metric in snapshot.metrics {
                        if let reset = metric.resetsAt,
                           !entity.expirations.metrics.contains(metric.id),
                           let deadline = absoluteDisplayDeadline(reset, wallNow: wall, monotonicNow: mono) {
                            next = min(next ?? .infinity, deadline)
                        }
                    }
                }
                for (index, balance) in snapshot.balances.enumerated() {
                    if let expiry = balance.expiresAt,
                       !entity.expirations.balances.contains(index),
                       let deadline = absoluteDisplayDeadline(expiry, wallNow: wall, monotonicNow: mono) {
                        next = min(next ?? .infinity, deadline)
                    }
                }
                for (index, credit) in (snapshot.resetCredits?.details ?? []).enumerated() {
                    if let expiry = credit.expiresAt,
                       !entity.expirations.credits.contains(index),
                       let deadline = absoluteDisplayDeadline(expiry, wallNow: wall, monotonicNow: mono) {
                        next = min(next ?? .infinity, deadline)
                    }
                }
            } else {
                rows.append(ProfileDisplay(profile: binding.profile, snapshot: nil, health: health,
                                           message: statusMessage, fetchedAge: nil))
            }
        }
        for (id, failure) in profileFailures {
            if let profile = configuredProfile(id) {
                rows.append(ProfileDisplay(profile: profile, snapshot: nil, health: failure.0, message: failure.1, fetchedAge: nil))
            }
        }
        let candidates = rankMetrics(snapshots, wallNow: wall, elapsedAges: ages, maximumCount: 8)
            .compactMap { ranked -> PresentationCandidate? in
                let key = ranked.providerID.rawValue + "\u{1f}" + ranked.accountID.rawValue
                guard let (deadline, id, expired) = proof[key],
                      !expired.metrics.contains(ranked.metric.id) else { return nil }
                return PresentationCandidate(metric: ranked, freshnessDeadline: deadline, snapshotGeneration: id)
            }
        return MonitorDisplay(profiles: rows.sorted { ($0.profile.providerID.rawValue, $0.profile.id) < ($1.profile.providerID.rawValue, $1.profile.id) },
                              candidates: candidates, revision: displayRevision, nextDisplayDeadline: next)
    }
    private func configuredProfile(_ id: String) -> AccountProfile? { configuredProfiles[id] }
    private func sourceMatches(_ profile: AccountProfile) -> Bool {
        switch (profile.providerID.rawValue, profile.source) {
        case ("codex", .codexFile(_)), ("claude", .claudeFile(_)), ("claude", .claudeDefaultDiscovery): return true
        default: return false
        }
    }
    private func armTick(_ deadline: TimeInterval?) {
        tickTask?.cancel(); tickTask = nil
        guard awake, let deadline, deadline.isFinite else { return }
        beforeDisplayArm?()
        let now = clock.monotonicNow()
        guard now.isFinite else { return }
        guard deadline > now else {
            if !crossedDeadlineQueued {
                crossedDeadlineQueued = true
                Task {
                    await Task.yield()
                    self.crossedDeadlineQueued = false
                    self.publish()
                }
            }
            return
        }
        guard let wait = DisplayWaitPolicy.interval(deadline: deadline, now: now) else { return }
        tickTask = Task {
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { self.publish() }
        }
    }
}

private func credentialMessage(_ error: Error) -> String {
    switch error {
    case CredentialFailure.expired: return "Session expired; reconnect account"
    case CredentialFailure.keychainDenied: return "Keychain access unavailable; choose Connect / Authorize"
    case CredentialFailure.accountMismatch: return "Configured account does not match session"
    default: return "Credential source unavailable"
    }
}
