import SwiftUI
import WidgetKit
import AppIntents

struct FinishNextStep: AppIntent {
    static var title: LocalizedStringResource = "设置事项进度"
    static var openAppWhenRun = false
    @Parameter(title: "事项 ID") var taskID: String
    @Parameter(title: "步骤 ID") var stepID: String
    init() {}
    init(taskID: String, stepID: String) { self.taskID = taskID; self.stepID = stepID }
    func perform() async throws -> some IntentResult {
        let url = try SharedDisk.location()
        _ = try SharedDisk.update(url) { archive in
            guard let i = archive.tasks.firstIndex(where: { $0.id.uuidString == taskID }), let id = UUID(uuidString: stepID) else { return }
            archive.tasks[i].setProgress(through: id)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
struct TaskEntry: TimelineEntry { let date: Date; var tasks: [TaskItem]; var failed = false; var categories = ["工作", "学习", "生活"] }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry { TaskEntry(date: Date(), tasks: [TaskItem(title: "准备下周的计划", category: "工作", steps: [Step(title: "收集想法", done: true), Step(title: "整理清单")]), TaskItem(title: "读书二十分钟", category: "学习", steps: [Step(title: "完成")])]) }
    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(900))))
    }
    func load() -> TaskEntry {
        do { let url = try SharedDisk.location(); let archive = try SharedDisk.transact(at: url) { try SharedDisk.read(url) }
            return TaskEntry(date: Date(), tasks: archive.tasks.filter { !$0.complete }, categories: archive.categories) }
        catch { return TaskEntry(date: Date(), tasks: [], failed: true) }
    }
}
struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry
    private let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private func categoryColor(_ name: String) -> Color {
        let rgb = CategoryColors.rgb(for: name, categories: entry.categories)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
    var isWide: Bool { family == .systemExtraLarge }
    var isPortrait: Bool { if #available(macOS 27.0, *) { return family == .systemExtraLargePortrait }; return false }
    var detailed: Bool { family == .systemLarge || isWide || isPortrait }
    var limit: Int { isWide || isPortrait ? 8 : family == .systemSmall ? 1 : family == .systemMedium ? 2 : 4 }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
            HStack {
                Label("StepNext", systemImage: "checkmark.square.fill").font(.headline).foregroundStyle(blue)
                Spacer(minLength: 4)
                if family != .systemSmall { Text("\(entry.tasks.count) 件待办").font(.caption2).foregroundStyle(.secondary) }

            }
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                Text(entry.failed ? "暂时无法读取事项" : "今天，也井井有条").font(.system(size: 14, weight: .semibold))
                Text(entry.failed ? "打开StepNext检查共享数据权限" : "在StepNext中添加你的第一件事").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                if isWide {
                    HStack(alignment: .top, spacing: 18) {
                        taskColumn(Array(entry.tasks.prefix(4)))
                        Divider()
                        taskColumn(Array(entry.tasks.dropFirst(4).prefix(4)))
                    }
                } else { taskColumn(Array(entry.tasks.prefix(limit))) }
                Spacer(minLength: 0)
                if entry.tasks.count > limit { Text("还有 \(entry.tasks.count - limit) 件待办").font(.caption2).foregroundStyle(.secondary) }
            }

        }.containerBackground(for: .widget) { LinearGradient(colors: [.white, Color(red: 0.92, green: 0.96, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
    func taskColumn(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tasks) { item in
                if family == .systemSmall {
                    HStack(alignment: .top, spacing: 7) {
                        Button(intent: FinishNextStep(taskID: item.id.uuidString, stepID: item.steps.first(where: { !$0.done })?.id.uuidString ?? "")) {
                            Image(systemName: "circle").font(.system(size: 18)).foregroundStyle(blue).frame(width: 21, height: 23)
                        }.buttonStyle(.plain).accessibilityLabel(item.steps.count > 1 ? "完成下一步：\(item.title)" : "完成：\(item.title)")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            HStack(spacing: 5) {
                                if let priority = item.priority { Text(priority.rawValue).foregroundStyle(priority == .urgent ? Color(red: 0.72, green: 0.25, blue: 0.06) : blue) }
                                if item.steps.count > 1 { Text("\(item.steps.filter(\.done).count)/\(item.steps.count)").foregroundStyle(.secondary) }
                            }.font(.system(size: 10, weight: .medium))
                            if item.steps.count > 1 { Text("下一步：\(item.steps.first(where: { !$0.done })?.title ?? "")").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Button(intent: FinishNextStep(taskID: item.id.uuidString, stepID: item.steps.first(where: { !$0.done })?.id.uuidString ?? "")) {
                            Image(systemName: "circle").font(.system(size: 18)).foregroundStyle(blue).frame(width: 20, height: 22)
                        }.buttonStyle(.plain).accessibilityLabel(item.steps.count > 1 ? "完成下一步：\(item.title)" : "完成：\(item.title)")
                        Text(item.category).font(.system(size: 9, weight: .medium)).foregroundStyle(categoryColor(item.category)).lineLimit(1).frame(maxWidth: 36)
                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(1)
                        if let priority = item.priority { Text(priority.rawValue).font(.system(size: 9, weight: .semibold)).foregroundStyle(priority == .urgent ? Color(red: 0.72, green: 0.25, blue: 0.06) : (priority == .normal ? blue : .secondary)).fixedSize() }
                        Spacer(minLength: 0)
                        if item.steps.count > 1 { Text("\(item.steps.filter(\.done).count)/\(item.steps.count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).fixedSize() }
                    }
                    if detailed && item.steps.count > 1 { chain(item) }
                    else if item.steps.count > 1 { Text("下一步：\(item.steps.first(where: { !$0.done })?.title ?? "")").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    else if !detailed { metadata(item) }
                }
                }
                if detailed && item.id != tasks.last?.id { Divider() }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    @ViewBuilder func metadata(_ item: TaskItem) -> some View {
        if let due = item.dueDate { Text(due, style: .date).font(.caption2).foregroundStyle(.secondary) }
        else { Text(item.dueText.isEmpty ? item.category : item.dueText).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
    }
    func chain(_ item: TaskItem) -> some View {
        let start = max(0, (item.steps.firstIndex(where: { !$0.done }) ?? 0) - 1)
        let visible = Array(item.steps.enumerated().dropFirst(start).prefix(4))
        return HStack(alignment: .top, spacing: 0) {
            ForEach(visible, id: \.element.id) { index, step in
                Button(intent: FinishNextStep(taskID: item.id.uuidString, stepID: step.id.uuidString)) {
                    VStack(spacing: 3) {
                        ZStack {
                            HStack(spacing: 0) {
                                Rectangle().fill(index > start ? blue.opacity(0.28) : Color.clear)
                                Rectangle().fill(index != visible.last?.offset ? blue.opacity(0.28) : Color.clear)
                            }.frame(height: 2)
                            Circle().fill(step.done ? blue : Color(red: 0.91, green: 0.95, blue: 1)).frame(width: 18, height: 18)
                            if step.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                            else { Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(blue) }
                        }
                        Text(step.title).font(.system(size: 9, weight: .medium)).foregroundStyle(.primary).lineLimit(1).frame(maxWidth: .infinity)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(step.title)，\(step.done ? "已完成" : "未完成")")
            }
        }.padding(.horizontal, 4)
    }
}
#if !SHIXU_TESTING
@main struct ShixuWidget: Widget {
    var sizes: [WidgetFamily] {
        var values: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(macOS 27.0, *) { values.append(.systemExtraLargePortrait) }
        return values
    }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShixuTasks", provider: Provider()) { entry in WidgetView(entry: entry) }
            .configurationDisplayName("StepNext待办").description("直接在桌面完成事项；点击步骤节点，设置当前完成进度。")
            .supportedFamilies(sizes)
    }
}

#endif
