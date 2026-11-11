import SwiftUI
import AppKit
import WidgetKit

enum Palette {
    static func category(_ name: String, categories: [String]) -> Color {
        let rgb = CategoryColors.rgb(for: name, categories: categories)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
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
    func reorder(_ orderedIDs: [UUID]) { change { $0.reorderTasks(orderedIDs) } }
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
struct Memo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var text = ""
    var updatedAt = Date()
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名备忘录" : title }
    var preview: String { text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "还没有内容" }
}
final class MemoStore: ObservableObject {
    @Published private(set) var notes: [Memo] = []
    @Published private(set) var pending = false
    @Published private(set) var error: String?
    let url: URL
    private var saveWork: DispatchWorkItem?
    private var loadFailed = false
    init(url: URL? = nil) {
        do {
            self.url = try url ?? SharedDisk.location().deletingLastPathComponent().appendingPathComponent("memos.json")
        } catch {
            self.url = SharedDisk.legacyURL.deletingLastPathComponent().appendingPathComponent("memos.json")
            self.error = "无法访问备忘录存储位置。"; loadFailed = true; return
        }
        do {
            notes = try SharedDisk.transact(at: self.url) {
                guard FileManager.default.fileExists(atPath: self.url.path) else { return [] }
                return try JSONDecoder().decode([Memo].self, from: Data(contentsOf: self.url))
            }
        } catch { self.error = "备忘录读取失败，原文件已保留：\(error.localizedDescription)"; loadFailed = true }
    }
    var editable: Bool { !loadFailed }
    @discardableResult func add() -> UUID? {
        guard editable else { return nil }
        let memo = Memo(); notes.insert(memo, at: 0); scheduleSave(); return memo.id
    }
    func update(_ id: UUID, title: String? = nil, text: String? = nil) {
        guard editable, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var memo = notes[index]
        if let title { memo.title = title }
        if let text { memo.text = text }
        guard memo != notes[index] else { return }
        memo.updatedAt = Date()
        notes[index] = memo
        scheduleSave()
    }
    func remove(_ id: UUID) { guard editable else { return }; notes.removeAll { $0.id == id }; scheduleSave(); flush() }
    private func scheduleSave() {
        pending = true; saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    @discardableResult func flush() -> Bool {
        saveWork?.cancel(); saveWork = nil
        guard pending else { return true }
        guard editable else { return false }
        do {
            let encoded = try JSONEncoder().encode(notes)
            try SharedDisk.transact(at: url) {
                if FileManager.default.fileExists(atPath: url.path) {
                    try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: .atomic)
                }
                try encoded.write(to: url, options: .atomic)
            }
            pending = false; error = nil; return true
        } catch { self.error = "备忘录保存失败：\(error.localizedDescription)"; return false }
    }
}
struct MemoWorkspace: View {
    @EnvironmentObject var memos: MemoStore
    @State private var selected: UUID?
    @State private var search = ""
    @State private var deleting: UUID?
    init(selected: UUID? = nil) { _selected = State(initialValue: selected) }
    var filtered: [Memo] { memos.notes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备忘录").font(.system(size: 30, weight: .bold))
                    Text("随手记下想法，慢慢展开。").foregroundStyle(.secondary)
                }
                Spacer()
                Button { search = ""; selected = memos.add() } label: { Label("新建备忘录", systemImage: "square.and.pencil") }
                    .buttonStyle(PrimaryButton()).keyboardShortcut("n").disabled(!memos.editable)
            }
            if let error = memos.error {
                HStack { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled); if memos.editable { Button("重试保存") { memos.flush() } } }
            }
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    TextField("搜索备忘录", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索备忘录")
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { memo in
                                Button { memos.flush(); selected = memo.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(memo.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(memo.preview).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                                        Text(memo.updatedAt, format: .dateTime.month().day().hour().minute()).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(selected == memo.id ? Palette.blue.opacity(0.1) : .white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected == memo.id ? Palette.blue.opacity(0.25) : .clear))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(memo.displayTitle)
                            }
                            if filtered.isEmpty { Text(search.isEmpty ? "还没有备忘录" : "没有匹配的备忘录").font(.caption).foregroundStyle(.secondary).padding(.vertical, 24) }
                        }
                    }
                }.padding(14).frame(width: 218)
                Divider()
                if let id = selected, memos.notes.contains(where: { $0.id == id }) {
                    MemoEditor(id: id, onDelete: { deleting = id }).id(id)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "note.text").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.blue)
                        Text("给想法留一页空白").font(.headline)
                        Text("新建备忘录，直接输入长文字。\n内容会自动保存在这台 Mac 上。").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if selected == nil { selected = memos.notes.first?.id } }
        .onDisappear { memos.flush() }
        .alert("删除这条备忘录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) { if let id = deleting { memos.remove(id); selected = memos.notes.first?.id }; deleting = nil }
        } message: { Text("这条备忘录的标题和正文将被移除。") }
    }
}
struct MemoEditor: View {
    @EnvironmentObject var memos: MemoStore
    let id: UUID
    var onDelete: () -> Void
    @FocusState private var titleFocused: Bool
    var memo: Memo? { memos.notes.first { $0.id == id } }
    var title: Binding<String> { Binding(get: { memo?.title ?? "" }, set: { memos.update(id, title: $0) }) }
    var text: Binding<String> { Binding(get: { memo?.text ?? "" }, set: { memos.update(id, text: $0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(memos.error != nil ? "尚未保存" : (memos.pending ? "保存中…" : "已自动保存"), systemImage: memos.error != nil ? "exclamationmark.circle" : (memos.pending ? "clock" : "checkmark.circle")).font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").frame(width: 24, height: 24) }.buttonStyle(.plain).help("删除备忘录").accessibilityLabel("删除备忘录")
            }
            TextField("标题", text: title).font(.system(size: 23, weight: .bold)).textFieldStyle(.plain).focused($titleFocused).accessibilityLabel("备忘录标题")
            Divider()
            MemoBodyInput(text: text, editable: memos.editable)
            HStack {
                Text("\(memo?.text.count ?? 0) 字").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("仅保存在本机").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity).disabled(!memos.editable)
        .onAppear { DispatchQueue.main.async { titleFocused = memo?.title.isEmpty == true } }
    }
}

struct MemoBodyInput: NSViewRepresentable {
    @Binding var text: String
    let editable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = BodyScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let editor = BodyTextView(frame: scroll.contentView.bounds)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .systemFont(ofSize: 15)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        editor.defaultParagraphStyle = paragraph
        editor.setAccessibilityLabel("备忘录正文")
        editor.string = text
        editor.delegate = context.coordinator
        editor.didEndComposition = { [weak coordinator = context.coordinator] editor in
            coordinator?.publish(editor)
        }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? BodyTextView else { return }
        context.coordinator.text = $text
        editor.isEditable = editable
        // AppKit owns the marked text and caret while the input method is composing.
        if !editor.isComposing, editor.string != text {
            editor.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? BodyTextView else { return }
            publish(editor)
        }

        func publish(_ editor: BodyTextView) {
            editor.needsDisplay = true
            guard !editor.isComposing, text.wrappedValue != editor.string else { return }
            text.wrappedValue = editor.string
        }
    }

    final class BodyScrollView: NSScrollView {
        override func layout() {
            super.layout()
            guard let editor = documentView as? NSTextView else { return }
            let height = contentView.bounds.height
            if editor.minSize.height != height {
                editor.minSize = NSSize(width: 0, height: height)
            }
            if editor.frame.height < height {
                editor.setFrameSize(NSSize(width: editor.frame.width, height: height))
            }
        }
    }

    final class BodyTextView: NSTextView {
        private var settingMarkedText = false
        private var insertingText = false
        var isComposing: Bool { settingMarkedText || insertingText || hasMarkedText() }
        var didEndComposition: ((BodyTextView) -> Void)?

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            settingMarkedText = true
            defer { settingMarkedText = false }
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            needsDisplay = true
        }

        override func insertText(_ string: Any, replacementRange: NSRange) {
            insertingText = true
            super.insertText(string, replacementRange: replacementRange)
            insertingText = false
            didEndComposition?(self)
        }

        override func unmarkText() {
            let wasComposing = hasMarkedText()
            super.unmarkText()
            if wasComposing { didEndComposition?(self) }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty else { return }
            let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                                 y: textContainerInset.height)
            ("从这里开始写，想写多长都可以…" as NSString).draw(at: origin, withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.placeholderTextColor
            ])
        }
    }
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
// Native drag lifecycle keeps cancelled/outside drops from changing saved order.
struct TaskFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct TaskDragHandle: NSViewRepresentable {
    var id: UUID
    var onBegin: () -> Void
    var onMove: (CGSize) -> Void
    var onEnd: (Bool) -> Void
    func makeNSView(context: Context) -> Handle { let view = Handle(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: Handle, context: Context) { view.onBegin = onBegin; view.onMove = onMove; view.onEnd = onEnd }
    final class Handle: NSView {
        var onBegin: () -> Void = {}
        var onMove: (CGSize) -> Void = { _ in }
        var onEnd: (Bool) -> Void = { _ in }
        private var origin = NSPoint.zero
        private var dragging = false
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")?.withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
            image?.draw(in: NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14))
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self); origin = event.locationInWindow; dragging = true; onBegin()
        }
        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            onMove(CGSize(width: event.locationInWindow.x - origin.x, height: origin.y - event.locationInWindow.y))
        }
        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }; mouseDragged(with: event); dragging = false; onEnd(true)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 && dragging { dragging = false; onEnd(false) } else { super.keyDown(with: event) }
        }
    }
}
struct TaskCard: View {
    @EnvironmentObject var store: Store
    var item: TaskItem
    var compact: Bool
    var edit: () -> Void
    var onReopen: () -> Void = {}
    var dragHandle: AnyView? = nil
    var moveUp: (() -> Void)? = nil
    var moveDown: (() -> Void)? = nil
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let dragHandle { dragHandle.frame(width: 20, height: 24).help("按住拖动，调整事项顺序").accessibilityLabel("拖动排序") }
                if item.complete || item.steps.count == 1 {
                    Button {
                        if item.complete {
                            if store.reopen(item.id) { onReopen() }
                        } else if let step = item.steps.first { store.setProgress(item.id, step.id) }
                    } label: {
                        Image(systemName: item.complete ? "checkmark.circle.fill" : "circle").font(.system(size: 21)).foregroundStyle(Palette.blue).frame(width: 24, height: 24)
                    }.buttonStyle(.plain).help(item.complete ? "设为未完成并返回进行中" : "完成事项").accessibilityLabel(item.complete ? "重新打开：\(item.title)" : "完成：\(item.title)")
                }
                Text(item.category).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.category(item.category, categories: store.data.categories)).lineLimit(1).frame(maxWidth: compact ? 36 : 65).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.category(item.category, categories: store.data.categories).opacity(0.08), in: Capsule()).help(item.category)
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
                Menu { if let moveUp { Button("上移", action: moveUp) }; if let moveDown { Button("下移", action: moveDown) }; Button("编辑事项", action: edit); Button("删除事项", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis").frame(width: 20, height: 24) }.menuStyle(.borderlessButton).frame(width: 20).help("事项操作")
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
    @EnvironmentObject var memos: MemoStore
    @State private var showingMemos = false
    var compact = false
    @State private var category = "全部事项"
    @State private var status = 0
    @State private var search = ""
    @State private var editing: TaskItem?
    @State private var newCategory = ""
    @State private var showingCategory = false
    @State private var draggingTask: UUID?
    @State private var previewOrder: [UUID]?
    @State private var taskFrames: [UUID: CGRect] = [:]
    @State private var dragSlots: [(UUID, CGRect)] = []
    @State private var dragInside = false
    @State private var dragInitialOrder: [UUID] = []
    var canReorder: Bool { category == "全部事项" && search.isEmpty }
    var displayItems: [TaskItem] {
        guard let previewOrder else { return items }
        let positions = Dictionary(uniqueKeysWithValues: previewOrder.enumerated().map { ($1, $0) })
        return items.enumerated().sorted {
            (positions[$0.element.id] ?? (previewOrder.count + $0.offset)) < (positions[$1.element.id] ?? (previewOrder.count + $1.offset))
        }.map(\.element)
    }
    var items: [TaskItem] { store.data.tasks.filter { (category == "全部事项" || $0.category == category) && (status == 2 || $0.complete == (status == 1)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        HStack(spacing: 0) {
            if !compact {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) { Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(Palette.blue); Text("StepNext").font(.title2.bold()) }.padding(.top, 18)
                    Text("把日子，一步步理顺。").font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 6) { categoryButton("全部事项", icon: "square.grid.2x2"); ForEach(store.data.categories, id: \.self) { categoryButton($0, icon: "folder") } }
                    Button { showingCategory = true } label: { Label("添加类别", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Divider()
                    Button { showingMemos = true } label: {
                        HStack { Image(systemName: "note.text"); Text("备忘录"); Spacer(); Text("\(memos.notes.count)").font(.caption).foregroundStyle(.secondary) }
                            .padding(11).contentShape(Rectangle()).foregroundStyle(showingMemos ? Palette.blue : Palette.ink)
                            .background(showingMemos ? Palette.blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { Delegate.shared.showWidget() } label: { Label("桌面小窗 · 支持贴边收纳", systemImage: "macwindow.on.rectangle") }.buttonStyle(.plain)
                    Label("本机保存", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                }.padding(22).frame(width: 204).background(.white.opacity(0.6)).overlay(alignment: .trailing) { Rectangle().fill(Palette.blue.opacity(0.08)).frame(width: 1) }
            }
            if showingMemos && !compact {
                MemoWorkspace()
            } else {
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
                        ForEach(displayItems) { item in
                            TaskCard(item: item, compact: compact, edit: { editing = item }, onReopen: { status = 0 },
                                dragHandle: canReorder ? AnyView(TaskDragHandle(id: item.id, onBegin: { startDragging(item.id) }, onMove: { updateDragging($0) }, onEnd: { finishDragging($0) })) : nil,
                                moveUp: canReorder && items.first?.id != item.id ? { moveTask(item.id, by: -1) } : nil,
                                moveDown: canReorder && items.last?.id != item.id ? { moveTask(item.id, by: 1) } : nil)
                                .opacity(draggingTask == item.id ? 0.65 : 1)
                                .background(GeometryReader { geometry in Color.clear.preference(key: TaskFrames.self, value: [item.id: geometry.frame(in: .named("taskList"))]) })
                        }
                    }.padding(.bottom, 8)
                }.coordinateSpace(name: "taskList").onPreferenceChange(TaskFrames.self) { taskFrames = $0 }.onExitCommand { finishDragging(false) }
            }.padding(compact ? 20 : 30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(.top, 28).background(Palette.mist.opacity(0.78)).background(Glass()).foregroundStyle(Palette.ink).preferredColorScheme(.light).tint(Palette.blue).sheet(item: $editing) { Editor(item: $0).environmentObject(store) }
        .alert("添加类别", isPresented: $showingCategory) { TextField("类别名称", text: $newCategory); Button("添加") { store.addCategory(newCategory); newCategory = "" }; Button("取消", role: .cancel) {} }
    }
    func startDragging(_ id: UUID) {
        guard canReorder else { return }
        previewOrder = items.map(\.id)
        dragInitialOrder = items.map(\.id)
        dragSlots = items.compactMap { item in taskFrames[item.id].map { (item.id, $0) } }
        dragInside = false
        draggingTask = id
    }
    func updateDragging(_ delta: CGSize) {
        guard let id = draggingTask, let source = dragSlots.first(where: { $0.0 == id }), var order = previewOrder,
              let from = order.firstIndex(of: id), !dragSlots.isEmpty else { return }
        let point = CGPoint(x: source.1.minX + 20 + delta.width, y: source.1.midY + delta.height)
        let bounds = dragSlots.map(\.1).reduce(CGRect.null) { $0.union($1) }
        dragInside = bounds.insetBy(dx: 0, dy: -8).contains(point)
        guard dragInside, let to = dragSlots.indices.min(by: { abs(dragSlots[$0].1.midY - point.y) < abs(dragSlots[$1].1.midY - point.y) }), let destination = dragInitialOrder.firstIndex(of: dragSlots[to].0), destination != from else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: destination > from ? destination + 1 : destination)
        previewOrder = order
    }
    func finishDragging(_ commit: Bool) {
        if commit && dragInside, let order = previewOrder, order != items.map(\.id) { store.reorder(order) }
        draggingTask = nil; previewOrder = nil; dragSlots = []; dragInitialOrder = []; dragInside = false
    }
    func moveTask(_ id: UUID, by delta: Int) {
        var order = items.map(\.id)
        guard let source = order.firstIndex(of: id), order.indices.contains(source + delta) else { return }
        order.swapAt(source, source + delta)
        store.reorder(order)
    }
    func summary(_ title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.blue).frame(width: 44, height: 44).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text("\(count)").font(.system(size: 24, weight: .semibold, design: .rounded)); Text(title).font(.caption).foregroundStyle(Palette.muted) }
            Spacer()
        }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }
    func categoryButton(_ name: String, icon: String) -> some View { Button { showingMemos = false; category = name } label: { HStack { Image(systemName: icon).foregroundStyle(Palette.category(name, categories: store.data.categories)); Text(name); Spacer(); Text("\(store.data.tasks.filter { !$0.complete && (name == "全部事项" || $0.category == name) }.count)").font(.caption).foregroundStyle(.secondary) }.padding(11).contentShape(Rectangle()).foregroundStyle(!showingMemos && category == name ? Palette.category(name, categories: store.data.categories) : Palette.ink).background(!showingMemos && category == name ? Palette.category(name, categories: store.data.categories).opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
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
    let memos = MemoStore()
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
        window.contentView = NSHostingView(rootView: Content(compact: compact).environmentObject(store).environmentObject(memos).ignoresSafeArea())
        let frameName = compact ? "widget" : "main"; if !window.setFrameUsingName(frameName) { window.center() }; window.setFrameAutosaveName(frameName)
        if compact { window.startEdgeTracking(); window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        return window
    }
    @objc func showMain() { main.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showWidget() { if widget == nil { widget = makeWindow(compact: true) }; (widget as? EdgeWindow)?.reveal(); widget?.makeKeyAndOrderFront(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if memos.flush() { return .terminateNow }
        showMain()
        let alert = NSAlert(); alert.messageText = "备忘录尚未保存"; alert.informativeText = memos.error ?? "请稍后重试保存，避免丢失修改。"; alert.addButton(withTitle: "返回应用"); alert.runModal()
        return .terminateCancel
    }
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
    let orderA = TaskItem(title: "排序 A", category: "工作", steps: [Step(title: "完成")])
    let orderB = TaskItem(title: "排序 B", category: "学习", steps: [Step(title: "完成", done: true)])
    let orderC = TaskItem(title: "排序 C", category: "工作", steps: [Step(title: "第一步", done: true), Step(title: "第二步")], priority: .urgent)
    let orderStore = Store(url: folder.appendingPathComponent("ordering.json"))
    orderStore.put(orderC); orderStore.put(orderB); orderStore.put(orderA)
    orderStore.reorder([orderC.id, orderA.id])
    assert(orderStore.data.tasks.map(\.id) == [orderC.id, orderB.id, orderA.id])
    assert(Store(url: orderStore.url).data.tasks.map(\.id) == [orderC.id, orderB.id, orderA.id])
    let staleOrder = Store(url: orderStore.url)
    orderStore.setProgress(orderC.id, orderC.steps[1].id)
    staleOrder.reorder([orderA.id, orderA.id, UUID(), orderC.id])
    let orderedResult = Store(url: orderStore.url)
    assert(orderedResult.data.tasks.map(\.id) == [orderA.id, orderB.id, orderC.id])
    assert(orderedResult.data.tasks.last!.complete && orderedResult.data.tasks.last!.priority == .urgent)
    let rgbWork = CategoryColors.rgb(for: "工作", categories: ["工作", "学习", "生活"])
    let rgbStudy = CategoryColors.rgb(for: "学习", categories: ["工作", "学习", "生活"])
    assert(rgbWork.0 != rgbStudy.0)
    let customBefore = CategoryColors.rgb(for: "爱好", categories: ["工作", "爱好"])
    let customAfter = CategoryColors.rgb(for: "爱好", categories: ["工作", "爱好", "旅行"])
    assert(customBefore.0 == customAfter.0 && customBefore.1 == customAfter.1 && customBefore.2 == customAfter.2)
    let another = CategoryColors.rgb(for: "旅行", categories: ["工作", "爱好", "旅行"])
    assert(customAfter.0 != another.0 || customAfter.1 != another.1 || customAfter.2 != another.2)
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
    let taskBytes = try! Data(contentsOf: url)
    let memoURL = folder.appendingPathComponent("memos.json")
    let memos = MemoStore(url: memoURL)
    let firstMemo = memos.add()!
    let longText = String(repeating: "这是一段长文字，支持中文、English、🙂。\n下一行继续记录。\n", count: 1200)
    memos.update(firstMemo, title: "长文测试", text: longText)
    assert(memos.pending && memos.flush() && !memos.pending)
    let secondMemo = memos.add()!
    memos.update(secondMemo, text: "另一条独立备忘录")
    assert(memos.flush())
    let loadedMemos = MemoStore(url: memoURL)
    assert(loadedMemos.notes.count == 2)
    assert(loadedMemos.notes.first(where: { $0.id == firstMemo })?.text == longText)
    assert(loadedMemos.notes.first(where: { $0.id == firstMemo })?.title == "长文测试")
    assert(loadedMemos.notes.first(where: { $0.id == secondMemo })?.displayTitle == "未命名备忘录")
    loadedMemos.remove(secondMemo)
    assert(MemoStore(url: memoURL).notes.map(\.id) == [firstMemo])
    assert((try! Data(contentsOf: url)) == taskBytes)
    assert(FileManager.default.fileExists(atPath: memoURL.appendingPathExtension("backup").path))
    let badMemoURL = folder.appendingPathComponent("malformed-memos.json")
    let malformed = Data("not valid JSON".utf8); try! malformed.write(to: badMemoURL)
    let invalidMemos = MemoStore(url: badMemoURL)
    assert(!invalidMemos.editable && invalidMemos.add() == nil && invalidMemos.flush())
    assert((try! Data(contentsOf: badMemoURL)) == malformed)
    let retryURL = folder.appendingPathComponent("retry-memos.json")
    let retryMemos = MemoStore(url: retryURL)
    try! FileManager.default.createDirectory(at: retryURL, withIntermediateDirectories: false)
    let retryID = retryMemos.add()!
    retryMemos.update(retryID, text: longText)
    assert(!retryMemos.flush() && retryMemos.pending && retryMemos.error != nil)
    try! FileManager.default.removeItem(at: retryURL)
    assert(retryMemos.flush() && !retryMemos.pending && retryMemos.error == nil)
    assert(MemoStore(url: retryURL).notes.first?.text == longText)
    print("PASS: memo long Unicode text, multiple notes, rename, reload, deletion, independent task data, backup, malformed-file protection, failed-save retry")
    try? FileManager.default.removeItem(at: folder)
    print("PASS: progress 3→2, prefix completion, repeated selection, persistence, final completion, single task, categories, stale merge, backup, optional priorities, legacy decode, first-stage reset to zero, reopen completed single and multi tasks, filtered reorder, persisted order, concurrent progress preserved")
} else {
    let app = NSApplication.shared
    let delegate = Delegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
