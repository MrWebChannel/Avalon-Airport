import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

// Plugin -> Finding -> (Proposal) -> Captain approves -> GroundCrew -> ActionRecord -> Event
//
// The PluginEngine lives inside the FlightTower on the Captain's device. It verifies package
// plugin signatures, loads the plugins of the boarding pass being evaluated (plugins ride on one
// Flight), runs them by type (security, analytics, contentBehavior) and limits what each type may
// output. Plugins never change Journey state: they only return Findings.

public enum PluginTrigger: String, Codable, Sendable { case onProposal, onEvent, onAppOpen, onSchedule }

public struct PluginContext {
    public var trigger: PluginTrigger
    public var now: Date
    public var journey: Journey
    public var boardingPass: BoardingPass?
    public var proposal: Proposal?
    public var credential: Credential?
    public var settings: [String: String] = [:]
}

public struct Recommendation: Hashable, Sendable {
    public var message: String
    public var statusChange: StatusChange?
    public var actions: [ActionRequest]
    public init(message: String, statusChange: StatusChange? = nil, actions: [ActionRequest] = []) {
        self.message = message; self.statusChange = statusChange; self.actions = actions
    }
}

public struct FindingDraft: Hashable, Sendable {
    public var severity: FindingSeverity
    public var message: String
    public var recommendation: Recommendation?
    public init(_ severity: FindingSeverity, _ message: String, recommendation: Recommendation? = nil) {
        self.severity = severity; self.message = message; self.recommendation = recommendation
    }
}

/// A plugin compiled into the app (default tier).
public protocol NativePlugin {
    var descriptor: PluginDescriptor { get set }
    func evaluate(_ context: PluginContext) -> [FindingDraft]
}

/// Runs package plugin scripts. The script must define `function evaluate(context)` returning an
/// array of `{severity, message, recommendation: {message, statusChange: {status, reason, cause}}}`.
/// No native functions are exposed to the script (no bridges to storage, network or notifications).
public protocol ScriptRuntime {
    func run(script: String, contextJSON: String) throws -> String
}

public enum PluginError: Error, LocalizedError {
    case runtimeUnavailable
    case script(String)
    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: return "JavaScript runtime unavailable on this platform"
        case .script(let message): return "Plugin script error: \(message)"
        }
    }
}

#if canImport(JavaScriptCore)
/// Sandboxed JavaScriptCore runtime: a fresh JSContext per run, nothing bridged in.
public final class JavaScriptCoreRuntime: ScriptRuntime {
    public init() {}
    public func run(script: String, contextJSON: String) throws -> String {
        guard let context = JSContext() else { throw PluginError.runtimeUnavailable }
        var thrown: String?
        context.exceptionHandler = { _, exception in thrown = exception?.toString() ?? "unknown error" }
        context.evaluateScript(script)
        if let thrown { throw PluginError.script(thrown) }
        context.setObject(contextJSON, forKeyedSubscript: "__avalonContext" as NSString)
        let result = context.evaluateScript(
            "JSON.stringify(typeof evaluate === 'function' ? (evaluate(JSON.parse(__avalonContext)) || []) : [])")
        if let thrown { throw PluginError.script(thrown) }
        guard let text = result?.toString(), text != "undefined" else { return "[]" }
        return text
    }
}
#endif

public struct EngineResult {
    public var findings: [Finding] = []
    public var raisedProposals: [Proposal] = []
    public var blocked: Bool { findings.contains { $0.severity == .block } }
    public var blockMessages: [String] { findings.filter { $0.severity == .block }.map(\.message) }
}

public final class PluginEngine {
    public let runOrder: [PluginType] = PluginType.allCases.sorted { $0.runRank < $1.runRank }
    public private(set) var defaults: [NativePlugin]
    public private(set) var packagePlugins: [String: PluginDescriptor] = [:]
    public private(set) var rejectedPlugins: [String: String] = [:]
    public var runtime: ScriptRuntime?

    public init(defaults: [NativePlugin] = PluginEngine.standardDefaults(), runtime: ScriptRuntime? = nil) {
        self.defaults = defaults
        #if canImport(JavaScriptCore)
        self.runtime = runtime ?? JavaScriptCoreRuntime()
        #else
        self.runtime = runtime
        #endif
    }

    public static func standardDefaults() -> [NativePlugin] {
        [SecurityPlugin(), FlightChecksPlugin(), DelayPlugin()]
    }

    public var loadedPluginIds: [String] { defaults.map(\.descriptor.id) + packagePlugins.keys.sorted() }

    public func descriptor(_ id: String) -> PluginDescriptor? {
        defaults.first { $0.descriptor.id == id }?.descriptor ?? packagePlugins[id]
    }

    /// Package plugins must carry a script whose SHA-256 matches their signature.
    public func verifySignature(_ plugin: PluginDescriptor) -> Bool {
        guard let script = plugin.script, let signature = plugin.signature else { return false }
        return Hashing.sha256(script) == signature
    }

    /// Registers a package plugin. Returns false and records the reason when it is rejected.
    @discardableResult
    public func register(_ plugin: PluginDescriptor) -> Bool {
        guard plugin.tier == .package else {
            rejectedPlugins[plugin.id] = "Only package plugins can be registered; defaults ship in the app"
            return false
        }
        guard !defaults.contains(where: { $0.descriptor.id == plugin.id }) else {
            rejectedPlugins[plugin.id] = "A package plugin cannot replace a default plugin"
            return false
        }
        guard verifySignature(plugin) else {
            rejectedPlugins[plugin.id] = "Signature does not match script"
            return false
        }
        packagePlugins[plugin.id] = plugin
        rejectedPlugins[plugin.id] = nil
        return true
    }

    /// Updates a default plugin's settings (for example the Delay plugin's graceHours).
    public func setDefaultSetting(pluginId: String, key: String, value: String) {
        for i in defaults.indices where defaults[i].descriptor.id == pluginId {
            defaults[i].descriptor.settings[key] = value
        }
    }

    public func setting(pluginId: String, key: String) -> String? {
        descriptor(pluginId)?.settings[key]
    }

    /// Runs every applicable plugin in run order and applies the per-type limits.
    /// Once a security plugin blocks, later types do not run.
    public func run(_ base: PluginContext) -> EngineResult {
        var result = EngineResult()
        let flightPluginIds = Set(base.boardingPass?.pluginIds ?? [])

        for type in runOrder {
            if result.blocked { break }
            let natives = defaults.filter { $0.descriptor.type == type }
            let scripts = packagePlugins.values
                .filter { $0.type == type && flightPluginIds.contains($0.id) }
                .sorted { $0.id < $1.id }

            for plugin in natives {
                var context = base
                context.settings = plugin.descriptor.settings
                collect(plugin.evaluate(context), from: plugin.descriptor, base: base, into: &result)
            }
            for plugin in scripts {
                var context = base
                context.settings = plugin.settings
                collect(runScript(plugin, context: context), from: plugin, base: base, into: &result)
            }
        }
        return result
    }

    private func collect(_ drafts: [FindingDraft], from plugin: PluginDescriptor, base: PluginContext,
                         into result: inout EngineResult) {
        for draft in drafts {
            // Enforce the type limit: contentBehavior may only inform, analytics may not block.
            let severity = min(draft.severity, plugin.type.maxSeverity)
            let finding = Finding(id: Ids.make("FN"), pluginId: plugin.id, pluginType: plugin.type,
                                  boardingPassId: base.boardingPass?.id, proposalId: base.proposal?.id,
                                  severity: severity, message: draft.message,
                                  recommendation: draft.recommendation?.message, createdAt: base.now)
            result.findings.append(finding)

            if let rec = draft.recommendation, plugin.type.mayRaiseProposal,
               rec.statusChange != nil || !rec.actions.isEmpty {
                var proposal = Proposal(boardingPassId: base.boardingPass?.id, authorId: plugin.id,
                                        authorType: .plugin, reportedAt: base.now, message: rec.message,
                                        statusChange: rec.statusChange, actionRequests: rec.actions)
                proposal.findingIds = [finding.id]
                result.raisedProposals.append(proposal)
            }
        }
    }

    private func runScript(_ plugin: PluginDescriptor, context: PluginContext) -> [FindingDraft] {
        guard let runtime, let script = plugin.script else {
            return [FindingDraft(.info, "\(plugin.name) skipped: no script runtime")]
        }
        do {
            let output = try runtime.run(script: script, contextJSON: ScriptContext.json(context))
            let decoded = try JSONDecoder().decode([ScriptFinding].self, from: Data(output.utf8))
            return decoded.map { $0.draft }
        } catch {
            return [FindingDraft(.info, "\(plugin.name) failed: \(error.localizedDescription)")]
        }
    }
}

// MARK: - What a script sees and returns

struct ScriptContext: Encodable {
    struct Pass: Encodable {
        var id, code, title, kind, status: String
        var eta: String?
        var waitingOn: String?
        var daysWaiting: Int?
        var daysToEta: Int?
    }
    var trigger: String
    var now: String
    var journeyTitle: String
    var boardingPass: Pass?
    var proposalMessage: String?
    var settings: [String: String]

    static func json(_ c: PluginContext) -> String {
        let iso = ISO8601DateFormatter()
        var pass: Pass?
        if let bp = c.boardingPass {
            pass = Pass(id: bp.id, code: bp.code, title: bp.title, kind: bp.kind.rawValue, status: bp.status.rawValue,
                        eta: bp.eta.map { iso.string(from: $0) }, waitingOn: bp.waitingOn?.kind.rawValue,
                        daysWaiting: bp.waitingOn.map { Calendar.current.dateComponents([.day], from: $0.since, to: c.now).day ?? 0 },
                        daysToEta: bp.eta.map { Calendar.current.dateComponents([.day], from: c.now, to: $0).day ?? 0 })
        }
        let value = ScriptContext(trigger: c.trigger.rawValue, now: iso.string(from: c.now), journeyTitle: c.journey.title,
                                  boardingPass: pass, proposalMessage: c.proposal?.message, settings: c.settings)
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

struct ScriptFinding: Decodable {
    struct Rec: Decodable {
        struct Change: Decodable { var status: String?; var reason: String?; var cause: String? }
        var message: String
        var statusChange: Change?
    }
    var severity: String
    var message: String
    var recommendation: Rec?

    var draft: FindingDraft {
        var rec: Recommendation?
        if let r = recommendation {
            var change: StatusChange?
            if let c = r.statusChange {
                change = StatusChange(status: c.status.flatMap(FlightStatus.init(rawValue:)), reason: c.reason,
                                      cause: c.cause.flatMap(WaitingCause.init(rawValue:)))
            }
            rec = Recommendation(message: r.message, statusChange: change)
        }
        return FindingDraft(FindingSeverity(rawValue: severity) ?? .info, message, recommendation: rec)
    }
}
