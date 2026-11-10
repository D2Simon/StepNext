import Foundation
@main struct Check {
    static func main() async throws {
        let url = try SharedDisk.location()
        let item = TaskItem(title: "Progress", category: "工作", steps: (1...4).map { Step(title: "\($0)") }, priority: .urgent)
        _ = try SharedDisk.update(url) { $0.tasks = [item] }
        _ = try await FinishNextStep(taskID: item.id.uuidString, stepID: item.steps[2].id.uuidString).perform()
        var saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.priority == .urgent)
        precondition(saved.steps.map(\.done) == [true, true, true, false])
        let backToTwo = FinishNextStep(taskID: item.id.uuidString, stepID: item.steps[1].id.uuidString)
        _ = try await backToTwo.perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.steps.map(\.done) == [true, true, false, false])
        _ = try await backToTwo.perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.steps.map(\.done) == [true, true, false, false])
        let first = FinishNextStep(taskID: item.id.uuidString, stepID: item.steps[0].id.uuidString)
        _ = try await first.perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.steps.map(\.done) == [true, false, false, false])
        _ = try await first.perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.steps.allSatisfy { !$0.done })
        precondition(saved.fraction == 0 && !saved.complete)
        _ = try await first.perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.steps.map(\.done) == [true, false, false, false])
        _ = try await FinishNextStep(taskID: item.id.uuidString, stepID: item.steps[3].id.uuidString).perform()
        saved = try SharedDisk.read(url).tasks[0]
        precondition(saved.complete)
        precondition(Provider().load().tasks.isEmpty)
        print("PASS: widget AppIntent 3→2, repeated selection stays at 2, selecting final step completes and removes task, first-stage on→off→on")
    }
}
