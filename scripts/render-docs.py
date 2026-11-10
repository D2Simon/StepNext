#!/usr/bin/env python3
"""Build an isolated, offscreen documentation renderer from the app's views.
No installed application or user task database is accessed.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
scratch = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.build' / 'docs-render'
scratch.mkdir(parents=True, exist_ok=True)
output = root / 'docs' / 'screenshots'
output.mkdir(parents=True, exist_ok=True)
source = (root / 'Source/main.swift').read_text().split('if CommandLine.arguments.contains("--self-test")')[0]
start = source.index('struct Glass:')
end = source.index('struct Editor:', start)
source = source[:start] + 'struct Glass: View { var body: some View { Palette.mist } }\n' + source[end:]
source = source.replace('ScrollView(.horizontal, showsIndicators: true) {', 'Group {')
source = source.replace('ScrollView {', 'Group {').replace('LazyVStack(spacing: 8)', 'VStack(spacing: 8)')
start = source.index('                Menu {')
end = source.index('\n            }', start)
source = source[:start] + '                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Palette.blue).frame(width: 20, height: 24)' + source[end:]
source = source.replace('AnyView(TaskDragHandle(id: item.id, onBegin: { startDragging(item.id) }, onMove: { updateDragging($0) }, onEnd: { finishDragging($0) }))', 'AnyView(Image(systemName: \"line.3.horizontal\").foregroundStyle(Palette.muted))')
lines = source.splitlines()
for index, line in enumerate(lines):
    if 'HStack { Picker("状态"' in line:
        lines[index] = '''                HStack {
                    HStack(spacing: 4) {
                        Text("进行中").foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 7).background(Palette.blue, in: RoundedRectangle(cornerRadius: 8))
                        Text("已完成").padding(.horizontal, 14)
                        Text("全部").padding(.horizontal, 14)
                    }.font(.system(size: 12, weight: .medium)).padding(3).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                    if !compact {
                        HStack { Image(systemName: "magnifyingglass"); Text("搜索事项"); Spacer() }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(10).frame(width: 160).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    }
                }'''
source = '\n'.join(lines).replace('ForEach(displayItems) { item in', 'ForEach(Array(displayItems.prefix(4))) { item in')
widget = (root / 'Widget/ShixuWidget.swift').read_text().split('#if !SHIXU_TESTING')[0]
widget = widget.replace('.containerBackground(for: .widget)', '.background').replace('@Environment(\\.widgetFamily) var family', 'var family: WidgetFamily = .systemLarge')
(scratch / 'WidgetViews.swift').write_text(widget)
source += r'''
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let store = Store(url: URL(fileURLWithPath: CommandLine.arguments[2]))
    store.data = Archive(categories: ["工作", "学习", "生活", "创作"], tasks: DemoData.items)
    @MainActor func save<V: View>(_ view: V, _ filename: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let rendered = renderer.nsImage, let tiff = rendered.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Rendering failed") }
        try! png.write(to: folder.appendingPathComponent(filename))
    }
    let overview = Content().environmentObject(store).frame(width: 1080, height: 800)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 7) { Circle().fill(Color.red.opacity(0.75)); Circle().fill(Color.orange.opacity(0.75)); Circle().fill(Color.green.opacity(0.75)) }.frame(width: 48, height: 10).padding(.leading, 18).padding(.top, 14)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
    save(overview, "overview.png")
    let cards = VStack(spacing: 8) { ForEach(Array(DemoData.items.prefix(4))) { TaskCard(item: $0, compact: false, edit: {}) } }
        .padding(20).frame(width: 760).fixedSize(horizontal: false, vertical: true).background(Palette.mist).environmentObject(store)
    save(cards, "tasks.png")
    let entry = TaskEntry(date: Date(timeIntervalSince1970: 0), tasks: DemoData.items.filter { !$0.complete })
    @MainActor func tile(_ family: WidgetFamily, _ width: CGFloat, _ height: CGFloat) -> some View {
        WidgetView(family: family, entry: entry).padding(14).frame(width: width, height: height).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.blue.opacity(0.1)))
    }
    let sizes = VStack(alignment: .leading, spacing: 20) {
        Text("A little space. A clear next step.").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.ink)
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) { Text("SMALL").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted); tile(.systemSmall, 170, 170) }
            VStack(alignment: .leading, spacing: 10) { Text("MEDIUM").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted); tile(.systemMedium, 360, 170) }
            VStack(alignment: .leading, spacing: 10) { Text("LARGE").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted); tile(.systemLarge, 360, 370) }
        }
    }.padding(28).background(Palette.mist)
    save(sizes, "widgets.png")
    save(tile(.systemExtraLarge, 760, 370).padding(24).background(Palette.mist), "extra-large.png")
}
'''.replace('\\.', '\\.')
# Raw Swift strings above use a single key-path backslash.
source = source.replace('\\\\.', '\\.')
(scratch / 'main.swift').write_text(source)
subprocess.run(['swiftc', str(scratch/'main.swift'), str(scratch/'WidgetViews.swift'), str(root/'Source/Shared.swift'), str(root/'Demo/DemoData.swift'), '-o', str(scratch/'render'), '-framework', 'SwiftUI', '-framework', 'AppKit', '-target', 'arm64-apple-macosx14.0'], check=True)
subprocess.run([str(scratch/'render'), str(output), str(scratch/'isolated-empty-store.json')], check=True)
print('Rendered fictional documentation views only:', output)
