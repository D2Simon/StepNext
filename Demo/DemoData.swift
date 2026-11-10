import Foundation

// Fictional documentation data only. Not compiled into or imported by the app.
enum DemoData {
    static var memos: [Memo] { [Memo(title: "周末的灵感清单", text: "给自己留一点慢下来的时间。\n\n想做的小事\n去公园走走，拍下树影和天空。\n找一家安静的咖啡馆，读完正在看的书。\n\n下周的想法\n把零散的灵感写下来，挑一件最想尝试的事。", updatedAt: Date(timeIntervalSince1970: 1794268800)), Memo(title: "读书摘记", text: "记录喜欢的一句话，再写下自己的理解。", updatedAt: Date(timeIntervalSince1970: 1794182400))] }

    static var items: [TaskItem] {
        [
            TaskItem(title: "准备周五的项目分享", category: "工作", dueText: "周五之前", steps: [Step(title: "整理想法", done: true), Step(title: "收集示例", done: true), Step(title: "制作幻灯片"), Step(title: "练习表达")], priority: .urgent),
            TaskItem(title: "完成一节摄影课程", category: "学习", dueText: "本周内", steps: [Step(title: "观看课程", done: true), Step(title: "拍摄练习"), Step(title: "整理笔记")], priority: .normal),
            TaskItem(title: "周末整理书桌", category: "生活", steps: [Step(title: "完成")], priority: .low),
            TaskItem(title: "给绿植浇水", category: "生活", steps: [Step(title: "完成")]),
            TaskItem(title: "写一篇旅行随笔", category: "创作", steps: [Step(title: "选题", done: true), Step(title: "列大纲", done: true), Step(title: "写初稿", done: true), Step(title: "润色")]),
            TaskItem(title: "准备下一周的计划", category: "生活", steps: [Step(title: "回顾本周", done: true), Step(title: "列出重点"), Step(title: "安排时间")], priority: .normal),
            TaskItem(title: "预约一次运动课程", category: "生活", steps: [Step(title: "完成")], priority: .low),
            TaskItem(title: "读一本短篇小说", category: "学习", steps: [Step(title: "选书", done: true), Step(title: "阅读"), Step(title: "记下一句话")]),
            TaskItem(title: "完成一次日落散步", category: "生活", steps: [Step(title: "完成", done: true)])
        ]
    }
}
