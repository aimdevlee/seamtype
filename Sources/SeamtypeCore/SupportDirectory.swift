import Foundation

/// `~/Library/Application Support/Seamtype`: settings, per-app rules, learned words and
/// AzooKey's kanji learning. `SEAMTYPE_SUPPORT_DIR` points a development copy (the settings
/// window, for screenshots) at another folder.
public enum SupportDirectory {
    public static var url: URL? {
        if let path = ProcessInfo.processInfo.environment["SEAMTYPE_SUPPORT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Seamtype", isDirectory: true)
    }
}
