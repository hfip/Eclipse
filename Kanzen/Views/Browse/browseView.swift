import SwiftUI

#if !os(tvOS)
struct BrowseView: View {
    @EnvironmentObject var moduleManager: ModuleManager
    let kanzen: KanzenEngine = KanzenEngine()
    var body: some View {
        NavigationView(){
            KanzenModuleView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(kanzen)
    }
}
#endif
