import Foundation
import HeavyCore

#if os(macOS)
import SwiftUI

@main
struct HeavyApp: App {
    @StateObject private var store = EditorStore()

    var body: some Scene {
        WindowGroup {
            HeavyEditorView(store: store)
                .frame(minWidth: 1100, minHeight: 720)
        }
    }
}
#else
@main
struct HeavyCLI {
    static func main() {
        let document = EditorDocument.sample()
        print("Heavy is a macOS writing app. Build this package on macOS to launch the SwiftUI editor.")
        print(document.plainText())
    }
}
#endif
