import Foundation
import Darwin
struct Step: Codable, Identifiable { var id = UUID(); var title: String; var done = false }
enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "紧急"
    case normal = "一般"
    case low = "不急"
}
// Category order is already persisted; appending categories preserves existing colors.
enum CategoryColors {
    static let presets = ["工作", "学习", "生活", "创作"]
    static func rgb(for category: String, categories: [String]) -> (Double, Double, Double) {
        switch category {
        case "工作", "全部事项": return (0.145, 0.388, 0.922)
        case "学习": return (0.486, 0.227, 0.929)
        case "生活": return (0.016, 0.471, 0.341)
        case "创作": return (0.761, 0.259, 0.047)
        default: break
        }
        let custom = categories.filter { !presets.contains($0) }
        let hash = category.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let index = custom.firstIndex(of: category) ?? Int(hash % 1000)
        let hue = (Double(index) * 137.507764 + 195).truncatingRemainder(dividingBy: 360) / 60
        let value = 0.48, saturation = 0.68
        let c = value * saturation, x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)), m = value - c
        let rgb: (Double, Double, Double)
        switch Int(hue) {
        case 0: rgb = (c, x, 0)
        case 1: rgb = (x, c, 0)
        case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c)
        case 4: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }
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
struct Archive: Codable {
    var categories = ["工作", "学习", "生活"]
    var tasks: [TaskItem] = []
    mutating func reorderTasks(_ orderedIDs: [UUID]) {
        let current = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var seen = Set<UUID>()
        let ordered = orderedIDs.compactMap { id -> TaskItem? in
            guard seen.insert(id).inserted else { return nil }
            return current[id]
        }
        let selected = Set(ordered.map(\.id))
        let slots = tasks.indices.filter { selected.contains(tasks[$0].id) }
        for (slot, task) in zip(slots, ordered) { tasks[slot] = task }
    }
}

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
