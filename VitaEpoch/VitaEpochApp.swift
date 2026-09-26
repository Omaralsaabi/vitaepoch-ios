import SwiftUI

@main
struct VitaEpochApp: App {
    @StateObject private var store: AppStore
    @StateObject private var bluetooth: X6CentralManager
    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _bluetooth = StateObject(wrappedValue: X6CentralManager(store: store))
    }
    var body: some Scene {
        WindowGroup {
            RootTabView().environmentObject(store).environmentObject(bluetooth).tint(.teal)
        }
    }
}
