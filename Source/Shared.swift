import Foundation
import Darwin
struct Step: Codable, Identifiable { var id = UUID(); var title: String; var done = false }
enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "紧急"
    case normal = "一般"
    case low = "不急"
}
struct TaskItem: Codable, Identifiable {
    var id = UUID(); var title: String; var category: String; var dueText = ""; var dueDate: Date?; var steps: [Step]; var priority: TaskPriority? = nil
    var complete: Bool { !steps.isEmpty && steps.allSatisfy(\.done) }
    var canResetProgress: Bool { steps.count > 1 && steps.first?.done == true && steps.dropFirst().allSatisfy { !$0.done } }
    mutating func setProgress(through stepID: UUID) {
        guard let target = steps.firstIndex(where: { $0.id == stepID }) else { return }
        let resetToStart = target == 0 && canResetProgress
        for index in steps.indices { steps[index].done = !resetToStart && index <= target }
    }
    mutating func reopen() {
        for index in steps.indices { steps[index].done = false }
    }
    mutating func useSingleCompletion() {
        let wasComplete = complete
        if steps.count == 1 && steps[0].title == "完成" { return }
        steps = [Step(title: "完成", done: wasComplete)]
    }
    var fraction: Double { steps.isEmpty ? 0 : Double(steps.filter(\.done).count) / Double(steps.count) }
}
struct Archive: Codable { var categories = ["工作", "学习", "生活"]; var tasks: [TaskItem] = [] }

enum SharedDisk {
    static let group = "group.local.shixu.app"
    static let legacyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shixu/tasks.json")
    static func location() throws -> URL {
        #if SHIXU_TESTING
        guard let path = ProcessInfo.processInfo.environment["SHIXU_TEST_DATA"] else { throw CocoaError(.fileNoSuchFile) }
        return URL(fileURLWithPath: path)
        #elseif LOCAL_WIDGET_BUILD
        #if WIDGET_EXTENSION
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shixu/tasks.json")
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/local.shixu.app.widget/Data/Library/Application Support/Shixu/tasks.json")
        #endif
        #elseif SIGNED_WIDGET_BUILD
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw CocoaError(.fileReadNoPermission) }
        return folder.appendingPathComponent("tasks.json")
        #else
        return legacyURL
        #endif
    }
    static func transact<T>(at url: URL, _ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try action()
    }
    static func read(_ url: URL) throws -> Archive {
        guard FileManager.default.fileExists(atPath: url.path) else { return Archive() }
        return try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
    }
    static func update(_ url: URL, _ change: (inout Archive) -> Void) throws -> Archive {
        try transact(at: url) {
            var archive = try read(url)
            change(&archive)
            if FileManager.default.fileExists(atPath: url.path) {
                let previous = try Data(contentsOf: url)
                try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
            }
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            return archive
        }
    }
}
