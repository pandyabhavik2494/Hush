import SwiftUI

@main
struct HushMacApp: App {
    var body: some Scene {
        Window("Hush", id: "main") {
            Text("Hush")
                .font(HushStyle.brandFont(size: 40))
                .foregroundStyle(HushStyle.gold)
                .frame(minWidth: 600, minHeight: 400)
                .background(HushStyle.paper)
        }
    }
}
