import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// Wraps JS execution for the `{{ }}` and `<js>`/`@js:` pipeline segments the rule DSL uses.
/// JavaScriptCore only exists on Apple platforms, so this type is written to compile everywhere
/// (needed for local engine development on Windows, where there's no Apple toolchain at all) but
/// only actually executes JS where the framework is present.
///
/// Not yet wired into `RuleEngine`/`RuleStringParser` — those still reject `{{ }}`/`<js>`/`@js:`
/// rules outright. This groundwork exists so that wiring is a small, isolated change once there's
/// real Mac access to verify it against actual JavaScriptCore behavior; writing the full `java.*`
/// binding surface (put/get/md5/base64/...) blind, with no way to run it, isn't worth the risk of
/// silent bugs that can't be caught until much later.
public enum JSRuntime {
    public static var isAvailable: Bool {
        #if canImport(JavaScriptCore)
        return true
        #else
        return false
        #endif
    }

    /// Evaluates `expression` with `bindings` available as global string variables, returning its
    /// string coercion.
    public static func evaluate(_ expression: String, bindings: [String: String]) throws -> String {
        #if canImport(JavaScriptCore)
        guard let context = JSContext() else {
            throw RuleEngineError.invalidRule("Failed to create a JSContext")
        }
        var caughtError: String?
        context.exceptionHandler = { _, exception in
            caughtError = exception?.toString() ?? "unknown JavaScriptCore error"
        }
        for (key, value) in bindings {
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
        let result = context.evaluateScript(expression)
        if let caughtError {
            throw RuleEngineError.invalidRule("JS evaluation failed: \(caughtError)")
        }
        return result?.toString() ?? ""
        #else
        throw RuleEngineError.notYetImplemented(
            "JavaScriptCore is unavailable on this platform (needs macOS/iOS) — cannot evaluate JS rules here"
        )
        #endif
    }
}
