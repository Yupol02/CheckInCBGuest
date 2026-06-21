import SwiftUI

/// Uygulama kökü `CheckingCBGuestsI_osApp` → `RootView` akışını kullanır.
/// Bu görünüm yalnızca Xcode önizleme/şablon uyumluluğu için korunur.
struct ContentView: View {
    var body: some View {
        RootView()
            .environment(AppDependencies.authViewModel)
    }
}

#Preview {
    ContentView()
}
