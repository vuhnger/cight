import Network

enum NetworkGate {
  static func waitUntilSatisfied(timeout: Duration) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { _ = try? await Task.sleep(for: timeout) }
      group.addTask {
        let monitor = NWPathMonitor()
        let updates = AsyncStream<NWPath.Status> { continuation in
          monitor.pathUpdateHandler = { continuation.yield($0.status) }
          continuation.onTermination = { _ in monitor.cancel() }
          monitor.start(queue: DispatchQueue(label: "com.vuhnger.cight.network"))
        }
        for await status in updates where status == .satisfied { return }
      }
      await group.next()
      group.cancelAll()
    }
  }
}
