import SwiftUI

@main
struct VitaEpochApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: AppStore
    @StateObject private var bluetooth: X6CentralManager
    init() {
        let store: AppStore
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            store = AppStore(url: URL.temporaryDirectory.appending(path: "VitaEpochUITests-\(UUID())/archive.json"),
                fixture: ProcessInfo.processInfo.environment["VITAEPOCH_TEST_ARCHIVE"].flatMap { Data(base64Encoded: $0) },
                queryDate: ProcessInfo.processInfo.environment["VITAEPOCH_TEST_NOW"].flatMap { ISO8601DateFormatter().date(from: $0) })
        } else { store = AppStore() }
        #else
        store = AppStore()
        #endif
        _store = StateObject(wrappedValue: store)
        _bluetooth = StateObject(wrappedValue: X6CentralManager(store: store))
    }
    var body: some Scene {
        WindowGroup {
            RootTabView().environmentObject(store).environmentObject(bluetooth).tint(.teal)
                .onChange(of: scenePhase) { _, phase in
                    // Persist on background and refresh date/range caches on foreground.
                    store.flush()
                }
        }
    }
}
