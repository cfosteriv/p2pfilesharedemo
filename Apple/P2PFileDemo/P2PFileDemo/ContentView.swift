import P2PFileSharingSDK
import SwiftUI

struct ContentView: View {
    @State private var controller = DemoControllerFactory.make()
    @State private var browserSessionID = UUID()

    var body: some View {
        DemoBrowserView(controller: controller) { statusMessage in
            let replacementController = DemoControllerFactory.make()
            replacementController.bannerMessage = statusMessage
            controller = replacementController
            browserSessionID = UUID()
        }
        .id(browserSessionID)
    }
}
