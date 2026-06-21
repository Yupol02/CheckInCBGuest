//
//  CheckingCBGuestsI_osApp.swift
//  CheckingCBGuestsİos
//

import FirebaseCore
import SwiftUI

@main
struct CheckingCBGuestsI_osApp: App {

    @State private var authViewModel: AuthViewModel

    init() {
        // Firebase, bağımlılık grafiği oluşturulmadan ÖNCE yapılandırılmalı;
        // property başlatıcıları init gövdesinden önce çalıştığı için
        // ViewModel ataması burada yapılır.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        _authViewModel = State(initialValue: AppDependencies.authViewModel)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
        }
    }
}
