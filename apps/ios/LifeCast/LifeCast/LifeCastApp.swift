//
//  LifeCastApp.swift
//  LifeCast
//
//  Created by Takeshi Hashimoto on 2026-02-12.
//

import SwiftUI

@main
struct LifeCastApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = LifeCastAPIClient.handleOAuthCallback(url: url)
                }
        }
    }
}
