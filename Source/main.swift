import SwiftUI
import AppKit
import WidgetKit

enum Palette {
    static func priority(_ value: TaskPriority) -> Color {
        switch value { case .urgent: return Color(red: 0.72, green: 0.25, blue: 0.06); case .normal: return blue; case .low: return muted }
    }
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let ink = Color(red: 0.09, green: 0.16, blue: 0.29)
    static let muted = Color(red: 0.32, green: 0.39, blue: 0.49)
    static let mist = Color(red: 0.93, green: 0.96, blue: 1)
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Palette.blue.opacity(!enabled ? 0.35 : (configuration.isPressed ? 0.75 : 1)), in: RoundedRectangle(cornerRadius: 11))
    }
}
final class Store: ObservableObject {
    @Published var data = Archive()
    @Published var error: String?
    let url: URL
    private var refreshTimer: Timer?
    init(url: URL? = nil) {
        var locationError: String?
        do { self.url = try url ?? SharedDisk.location() }
        catch { self.url = SharedDisk.legacyURL; locationError = "无法访问小组件共享数据，请检查 App Group 签名。" }
        do {
            #if SIGNED_WIDGET_BUILD
            if url == nil && !FileManager.default.fileExists(atPath: self.url.path) && FileManager.default.fileExists(atPath: SharedDisk.legacyURL.path) {
                let previous = try SharedDisk.read(SharedDisk.legacyURL)
                _ = try SharedDisk.update(self.url) { $0 = previous }
            }
            #endif
            data = try SharedDisk.transact(at: self.url) { try SharedDisk.read(self.url) }
        } catch { self.error = "读取失败，原文件已保留：\(error.localizedDescription)" }
        if let locationError { error = locationError }
        if url == nil { refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reload() } }
    }
    func reload() {
        guard error == nil else { return }
        do {
            let fresh = try SharedDisk.transact(at: url) { try SharedDisk.read(url) }
            if try JSONEncoder().encode(fresh) != JSONEncoder().encode(data) { data = fresh }
        } catch { self.error = "读取失败：\(error.localizedDescription)" }
    }
    func change(_ action: (inout Archive) -> Void) {
        guard error == nil else { return }
        do { data = try SharedDisk.update(url, action); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func put(_ item: TaskItem) { change { archive in if let i = archive.tasks.firstIndex(where: {$0.id == item.id}) { archive.tasks[i] = item } else { archive.tasks.insert(item, at: 0) } } }
    func remove(_ id: UUID) { change { $0.tasks.removeAll { $0.id == id } } }
    func setProgress(_ task: UUID, _ step: UUID) { change { archive in
        guard let i = archive.tasks.firstIndex(where: { $0.id == task }) else { return }
        archive.tasks[i].setProgress(through: step)
    } }
    @discardableResult func reopen(_ task: UUID) -> Bool {
        change { archive in
            guard let index = archive.tasks.firstIndex(where: { $0.id == task }), archive.tasks[index].complete else { return }
            archive.tasks[index].reopen()
        }
        return error == nil && data.tasks.contains { $0.id == task && !$0.complete }
    }
    func addCategory(_ text: String) { let name = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; change { if !$0.categories.contains(name) { $0.categories.append(name) } } }
}
struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView { let v = NSVisualEffectView(); v.material = .underWindowBackground; v.blendingMode = .behindWindow; v.state = .active; return v }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct Editor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var item: TaskItem
    @State private var splitProgress = false
    @State private var mode = 0
    @State private var date = Date()
    @State private var categoryName = ""
    @FocusState private var titleFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(item.title.isEmpty ? "一件新的事" : "编辑事项").font(.title2.bold()); Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("事项名称").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            TextField("给这件事起个名字", text: $item.title).font(.title3).textFieldStyle(.roundedBorder).focused($titleFocused)
            HStack { Text("分类"); Picker("分类", selection: $item.category) { ForEach(store.data.categories, id: \.self) { Text($0).tag($0) } }.labelsHidden(); Spacer() }
            Picker("优先级 · 可选", selection: $item.priority) {
                Text("不设置").tag(TaskPriority?.none)
                ForEach(TaskPriority.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.segmented)
            HStack { TextField("新类别，如：个人项目", text: $categoryName); Button("添加类别") { store.addCategory(categoryName); let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines); if store.data.categories.contains(name) { item.category = name; categoryName = "" } }.disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            VStack(alignment: .leading, spacing: 10) {
                Text("截止时间 · 可选").font(.headline)
                Picker("截止方式", selection: $mode) { Text("不设置").tag(0); Text("具体日期").tag(1); Text("一句话").tag(2) }.pickerStyle(.segmented)
                if mode == 1 { DatePicker("截止日期", selection: $date, displayedComponents: [.date]).environment(\.locale, Locale(identifier: "zh_CN")) }
                if mode == 2 { TextField("例如：这周内 / 下次开会前", text: $item.dueText).textFieldStyle(.roundedBorder) }
            }
            Toggle("拆分为多个进度（可选）", isOn: $splitProgress)
            if splitProgress {
            HStack { Text("拆成几个小进度").font(.headline); Spacer(); Text("点击节点，设置完成到哪一步").font(.caption).foregroundStyle(.secondary) }
            ScrollView { VStack(spacing: 10) { ForEach($item.steps) { $step in
                HStack { Image(systemName: step.done ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary); TextField("进度名称", text: $step.title).textFieldStyle(.roundedBorder); Button { item.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("移除此进度").disabled(item.steps.count == 1) }
            } } }.frame(minHeight: 90, maxHeight: 180)
            Button { item.steps.append(Step(title: "")) } label: { Label("添加一个进度", systemImage: "plus") }
            } else {
                Label("无需拆分，保存后勾选「完成」即可。", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack { Text("写下事项，就可以开始。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("保存事项") { item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines); item.steps = item.steps.map { var s = $0; s.title = s.title.trimmingCharacters(in: .whitespacesAndNewlines); return s }; if !splitProgress { item.useSingleCompletion() }; item.dueDate = mode == 1 ? date : nil; if mode != 2 { item.dueText = "" }; store.put(item); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(PrimaryButton()).disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (splitProgress && (item.steps.isEmpty || item.steps.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))) }
        }.padding(28).frame(width: 520).background(Palette.mist.opacity(0.6)).tint(Palette.blue).preferredColorScheme(.light).onAppear { splitProgress = !(item.steps.count == 1 && item.steps[0].title == "完成"); mode = item.dueDate != nil ? 1 : (item.dueText.isEmpty ? 0 : 2); date = item.dueDate ?? Date(); titleFocused = true }
    }
}
struct TaskCard: View {
    @EnvironmentObject var store: Store
    var item: TaskItem
    var compact: Bool
    var edit: () -> Void
    var onReopen: () -> Void = {}
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if item.complete || item.steps.count == 1 {
                    Button {
                        if item.complete {
                            if store.reopen(item.id) { onReopen() }
                        } else if let step = item.steps.first { store.setProgress(item.id, step.id) }
                    } label: {
                        Image(systemName: item.complete ? "checkmark.circle.fill" : "circle").font(.system(size: 21)).foregroundStyle(Palette.blue).frame(width: 24, height: 24)
                    }.buttonStyle(.plain).help(item.complete ? "设为未完成并返回进行中" : "完成事项").accessibilityLabel(item.complete ? "重新打开：\(item.title)" : "完成：\(item.title)")
                }
                Text(item.category).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.blue).lineLimit(1).frame(maxWidth: compact ? 36 : 65).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.blue.opacity(0.08), in: Capsule()).help(item.category)
                Text(item.title).font(.system(size: 14, weight: .semibold)).strikethrough(item.complete).foregroundStyle(item.complete ? .secondary : .primary).lineLimit(1).help(item.title).layoutPriority(1)
                if let priority = item.priority {
                    Text(priority.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.priority(priority)).fixedSize()
                }
                Spacer(minLength: 0)
                if item.steps.count > 1 {
                    Text("\(item.steps.filter(\.done).count)/\(item.steps.count) 已完成").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                }
                if let due = item.dueDate {
                    Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(!item.complete && Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date()) ? Color.orange : Color.secondary).help("DDL：\(due.formatted(date: .abbreviated, time: .omitted))")
                } else if !item.dueText.isEmpty { Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.secondary).help("DDL：\(item.dueText)") }
                Menu { Button("编辑事项", action: edit); Button("删除事项", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis").frame(width: 20, height: 24) }.menuStyle(.borderlessButton).frame(width: 20).help("事项操作")
            }
            if item.steps.count > 1 {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
                            Button { store.setProgress(item.id, step.id) } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        HStack(spacing: 0) {
                                            Rectangle().fill(index > 0 ? (item.steps[index - 1].done && step.done ? Palette.blue : Palette.blue.opacity(0.18)) : Color.clear)
                                            Rectangle().fill(index < item.steps.count - 1 ? (step.done && item.steps[index + 1].done ? Palette.blue : Palette.blue.opacity(0.18)) : Color.clear)
                                        }.frame(width: compact ? 64 : 84, height: 3)
                                        Circle().fill(step.done ? Palette.blue : Palette.mist).frame(width: 25, height: 25)
                                        Circle().strokeBorder(Palette.blue.opacity(step.done ? 1 : 0.3), lineWidth: 1.5).frame(width: 25, height: 25)
                                        if step.done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                                        else { Text("\(index + 1)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Palette.blue) }
                                    }
                                    Text(step.title).font(.system(size: 11, weight: .medium)).foregroundStyle(step.done ? Palette.muted : Palette.ink).multilineTextAlignment(.center).lineLimit(1).frame(width: compact ? 64 : 84)
                                }.padding(.vertical, 2).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(index == 0 && item.canResetProgress ? "取消第 1 步，回到未开始" : "设置完成到：\(step.title)").accessibilityLabel("第 \(index + 1) 步，\(step.title)，\(step.done ? "已完成" : "未完成")")
                            if index < item.steps.count - 1 {
                                Capsule().fill(step.done && item.steps[index + 1].done ? Palette.blue : Palette.blue.opacity(0.18)).frame(width: compact ? 14 : 24, height: 3).padding(.top, 13)
                            }
                        }
                    }.padding(.bottom, 3)
                }
            }
        }.padding(12).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.blue.opacity(0.09))).shadow(color: Palette.blue.opacity(0.035), radius: 10, y: 4).confirmationDialog("删除「\(item.title)」？", isPresented: $deleting) { Button("删除", role: .destructive) { store.remove(item.id) } } message: { Text("删除后无法恢复。") }
    }
}
struct Content: View {
    @EnvironmentObject var store: Store
    var compact = false
    @State private var category = "全部事项"
    @State private var status = 0
    @State private var search = ""
    @State private var editing: TaskItem?
    @State private var newCategory = ""
    @State private var showingCategory = false
    var items: [TaskItem] { store.data.tasks.filter { (category == "全部事项" || $0.category == category) && (status == 2 || $0.complete == (status == 1)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        HStack(spacing: 0) {
            if !compact {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) { Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(Palette.blue); Text("StepNext").font(.title2.bold()) }.padding(.top, 18)
                    Text("把日子，一步步理顺。").font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 6) { categoryButton("全部事项", icon: "square.grid.2x2"); ForEach(store.data.categories, id: \.self) { categoryButton($0, icon: "folder") } }
                    Button { showingCategory = true } label: { Label("添加类别", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    Button { Delegate.shared.showWidget() } label: { Label("桌面小窗 · 支持贴边收纳", systemImage: "macwindow.on.rectangle") }.buttonStyle(.plain)
                    Label("本机保存", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                }.padding(22).frame(width: 204).background(.white.opacity(0.6)).overlay(alignment: .trailing) { Rectangle().fill(Palette.blue.opacity(0.08)).frame(width: 1) }
            }
            VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text(compact ? "StepNext · 桌面" : category).font(.system(size: compact ? 21 : 30, weight: .bold)); if !compact { Text("\(store.data.tasks.filter { !$0.complete }.count) 件进行中，给每一小步留点空间。").foregroundStyle(.secondary) } }; Spacer(); Button { editing = TaskItem(title: "", category: category == "全部事项" ? (store.data.categories.first ?? "生活") : category, steps: [Step(title: "完成")]) } label: { Label(compact ? "添加" : "新建事项", systemImage: "plus") }.buttonStyle(PrimaryButton()).keyboardShortcut("n") }
                if !compact {
                    HStack(spacing: 12) {
                        summary("进行中", count: store.data.tasks.filter { !$0.complete && (category == "全部事项" || $0.category == category) }.count, icon: "circle.dotted")
                        summary("已完成", count: store.data.tasks.filter { $0.complete && (category == "全部事项" || $0.category == category) }.count, icon: "checkmark.circle")
                    }
                }
                HStack { Picker("状态", selection: $status) { Text("进行中").tag(0); Text("已完成").tag(1); Text("全部").tag(2) }.pickerStyle(.segmented); if !compact { TextField("搜索事项", text: $search).textFieldStyle(.roundedBorder).frame(width: 170) } }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if items.isEmpty { VStack(spacing: 16) { Image(systemName: status == 1 ? "checkmark.seal" : "leaf").font(.system(size: 38, weight: .light)).foregroundStyle(Palette.blue); Text(search.isEmpty ? (status == 1 ? "完成的小事会收在这里" : "从一件小事开始") : "没有找到匹配的事项").font(.headline); Text("点击上方 +，写下要做的事。").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 65) }
                        ForEach(items) { item in TaskCard(item: item, compact: compact, edit: { editing = item }, onReopen: { status = 0 }) }
                    }.padding(.bottom, 8)
                }
            }.padding(compact ? 20 : 30).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.top, 28).background(Palette.mist.opacity(0.78)).background(Glass()).foregroundStyle(Palette.ink).preferredColorScheme(.light).tint(Palette.blue).sheet(item: $editing) { Editor(item: $0).environmentObject(store) }
        .alert("添加类别", isPresented: $showingCategory) { TextField("类别名称", text: $newCategory); Button("添加") { store.addCategory(newCategory); newCategory = "" }; Button("取消", role: .cancel) {} }
    }
    func summary(_ title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.blue).frame(width: 44, height: 44).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text("\(count)").font(.system(size: 24, weight: .semibold, design: .rounded)); Text(title).font(.caption).foregroundStyle(Palette.muted) }
            Spacer()
        }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }
    func categoryButton(_ name: String, icon: String) -> some View { Button { category = name } label: { HStack { Image(systemName: icon); Text(name); Spacer(); Text("\(store.data.tasks.filter { !$0.complete && (name == "全部事项" || $0.category == name) }.count)").font(.caption).foregroundStyle(.secondary) }.padding(11).contentShape(Rectangle()).foregroundStyle(category == name ? Palette.blue : Palette.ink).background(category == name ? Palette.blue.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
}

final class EdgeWindow: NSWindow {
    private var poller: Timer?
    private var dockEdge: Int = 0
    private var tucked = false
    private var expandedFrame = NSRect.zero
    private var outsideSince: Date?
    func startEdgeTracking() {
        poller = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkEdge() }
    }
    private func checkEdge() {
        guard isVisible, !isMiniaturized, attachedSheet == nil else { return }
        let mouse = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons != 0 {
            if !tucked { dockEdge = 0; outsideSince = nil }
            return
        }
        guard let bounds = screen?.visibleFrame else { return }
        if tucked {
            if frame.contains(mouse) {
                tucked = false
                setFrame(expandedFrame, display: true, animate: true)
                outsideSince = nil
            }
            return
        }
        if abs(frame.minX - bounds.minX) < 26 { dockEdge = -1 }
        else if abs(frame.maxX - bounds.maxX) < 26 { dockEdge = 1 }
        else { dockEdge = 0 }
        guard dockEdge != 0 else { outsideSince = nil; return }
        if frame.insetBy(dx: -5, dy: -5).contains(mouse) { outsideSince = nil; return }
        if outsideSince == nil { outsideSince = Date(); return }
        guard Date().timeIntervalSince(outsideSince!) > 0.8 else { return }
        expandedFrame = frame
        expandedFrame.origin.x = dockEdge == -1 ? bounds.minX : bounds.maxX - frame.width
        expandedFrame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
        var hidden = expandedFrame
        hidden.origin.x = dockEdge == -1 ? bounds.minX - frame.width + 8 : bounds.maxX - 8
        tucked = true
        setFrame(hidden, display: true, animate: true)
    }
    func reveal() {
        if tucked { tucked = false; setFrame(expandedFrame, display: true) }
        outsideSince = nil
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    static var shared: Delegate!
    let store = Store()
    var main: NSWindow!
    var widget: NSWindow?
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        Delegate.shared = self
        let bar = NSMenu()
        let appEntry = NSMenuItem(); let appMenu = NSMenu(); appMenu.addItem(withTitle: "退出StepNext", action: #selector(quit), keyEquivalent: "q").target = self; appEntry.submenu = appMenu; bar.addItem(appEntry)
        let editEntry = NSMenuItem(); editEntry.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        editEntry.submenu = editMenu; bar.addItem(editEntry); NSApp.mainMenu = bar
        main = makeWindow(compact: false)
        main.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "StepNext")
        let menu = NSMenu(); menu.addItem(withTitle: "打开StepNext", action: #selector(showMain), keyEquivalent: ""); menu.addItem(withTitle: "桌面小窗", action: #selector(showWidget), keyEquivalent: ""); menu.addItem(.separator()); menu.addItem(withTitle: "退出StepNext", action: #selector(quit), keyEquivalent: "q"); for i in menu.items { i.target = self }; statusItem.menu = menu
    }
    func makeWindow(compact: Bool) -> NSWindow {
        let window = EdgeWindow(contentRect: NSRect(x: 0, y: 0, width: compact ? 390 : 960, height: compact ? 600 : 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.title = compact ? "StepNext · 桌面小窗" : "StepNext"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none; window.isOpaque = false; window.backgroundColor = .clear; window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: compact ? 340 : 780, height: 440)
        window.contentView = NSHostingView(rootView: Content(compact: compact).environmentObject(store).ignoresSafeArea())
        let frameName = compact ? "widget" : "main"; if !window.setFrameUsingName(frameName) { window.center() }; window.setFrameAutosaveName(frameName)
        if compact { window.startEdgeTracking(); window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        return window
    }
    @objc func showMain() { main.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showWidget() { if widget == nil { widget = makeWindow(compact: true) }; (widget as? EdgeWindow)?.reveal(); widget?.makeKeyAndOrderFront(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
}
if CommandLine.arguments.contains("--self-test") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = folder.appendingPathComponent("tasks.json")
    let store = Store(url: url)
    let item = TaskItem(title: "测试", category: "工作", dueText: "本周", steps: (1...4).map { Step(title: "步骤\($0)") })
    store.put(item)
    store.setProgress(item.id, item.steps[2].id)
    assert(store.data.tasks[0].steps.map(\.done) == [true, true, true, false])
    store.setProgress(item.id, item.steps[1].id)
    assert(store.data.tasks[0].steps.map(\.done) == [true, true, false, false])
    store.setProgress(item.id, item.steps[1].id)
    assert(store.data.tasks[0].steps.map(\.done) == [true, true, false, false])
    let restored = Store(url: url)
    assert(restored.data.tasks[0].steps.map(\.done) == [true, true, false, false])
    assert(restored.data.tasks[0].dueText == "本周")
    restored.setProgress(item.id, item.steps[0].id)
    assert(restored.data.tasks[0].steps.map(\.done) == [true, false, false, false])
    restored.setProgress(item.id, item.steps[0].id)
    assert(restored.data.tasks[0].steps.allSatisfy { !$0.done })
    assert(Store(url: url).data.tasks[0].fraction == 0)
    restored.setProgress(item.id, item.steps[0].id)
    assert(restored.data.tasks[0].steps.map(\.done) == [true, false, false, false])
    restored.setProgress(item.id, item.steps[3].id)
    assert(restored.data.tasks[0].complete)
    let completedSnapshot = restored.data.tasks[0]
    assert(restored.reopen(item.id))
    assert(restored.data.tasks[0].steps.allSatisfy { !$0.done })
    assert(restored.data.tasks[0].title == completedSnapshot.title)
    assert(restored.data.tasks[0].dueText == completedSnapshot.dueText)
    assert(restored.data.tasks[0].steps.map(\.id) == completedSnapshot.steps.map(\.id))
    assert(!Store(url: url).data.tasks[0].complete)
    restored.addCategory("自定义"); restored.addCategory("自定义")
    assert(restored.data.categories.filter { $0 == "自定义" }.count == 1)
    var single = TaskItem(title: "单项", category: "生活", steps: [])
    assert(!single.complete); single.useSingleCompletion()
    assert(single.steps.count == 1 && !single.complete)
    single.setProgress(through: single.steps[0].id); assert(single.complete)
    single.setProgress(through: single.steps[0].id); assert(single.complete)
    restored.put(single)
    assert(restored.reopen(single.id))
    assert(!Store(url: url).data.tasks.first(where: { $0.id == single.id })!.complete)
    var priorityItem = single
    for priority in TaskPriority.allCases {
        priorityItem.priority = priority
        restored.put(priorityItem)
        let reloaded = Store(url: url)
        assert(reloaded.data.tasks.first(where: { $0.id == priorityItem.id })?.priority == priority)
    }
    priorityItem.priority = nil; restored.put(priorityItem)
    assert(Store(url: url).data.tasks.first(where: { $0.id == priorityItem.id })?.priority == nil)
    let old = Data("{\"title\":\"旧数据\",\"id\":\"00000000-0000-0000-0000-000000000001\",\"category\":\"工作\",\"dueText\":\"\",\"steps\":[]}".utf8)
    let decoded = try! JSONDecoder().decode(TaskItem.self, from: old)
    assert(decoded.priority == nil)
    let stale = Store(url: url)
    restored.addCategory("并发分类")
    stale.put(single)
    let merged = Store(url: url)
    assert(merged.data.categories.contains("并发分类"))
    assert(merged.data.tasks.contains { $0.id == single.id })
    assert((try? SharedDisk.read(url.appendingPathExtension("backup"))) != nil)
    try? FileManager.default.removeItem(at: folder)
    print("PASS: progress 3→2, prefix completion, repeated selection, persistence, final completion, single task, categories, stale merge, backup, optional priorities, legacy decode, first-stage reset to zero, reopen completed single and multi tasks")
} else {
    let app = NSApplication.shared
    let delegate = Delegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
