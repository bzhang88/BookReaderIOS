import Foundation

/// How a store's write method treats an id that already exists locally -- the two shapes actually
/// used across this app's stores (see each store's `add`): most rule/config stores upsert in place,
/// while a couple of pure-log-like stores (bookmarks, local books) only ever append and rely on the
/// caller to dedupe.
public enum RestoreMergeStyle {
    case upsert
    case appendDedup
}

public struct RestoreDiff: Equatable {
    public let willInsert: Int
    public let willUpdate: Int
    public let willSkip: Int

    public init(willInsert: Int, willUpdate: Int, willSkip: Int) {
        self.willInsert = willInsert
        self.willUpdate = willUpdate
        self.willSkip = willSkip
    }
}

/// Pure counting logic behind the backup restore preview -- lets `BackupSettingsView` show "远端 N
/// 项 → 新增 X / 更新 Y" before the user commits to overwriting anything, without needing a real
/// store or network round-trip to test.
public enum RestorePreviewCalculator {
    public static func diff(remoteIds: [String], localIds: Set<String>, style: RestoreMergeStyle) -> RestoreDiff {
        let matching = remoteIds.filter { localIds.contains($0) }.count
        switch style {
        case .upsert:
            return RestoreDiff(willInsert: remoteIds.count - matching, willUpdate: matching, willSkip: 0)
        case .appendDedup:
            return RestoreDiff(willInsert: remoteIds.count - matching, willUpdate: 0, willSkip: matching)
        }
    }
}
