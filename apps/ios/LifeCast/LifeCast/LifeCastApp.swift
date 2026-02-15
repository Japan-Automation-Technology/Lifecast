//
//  LifeCastApp.swift
//  LifeCast
//
//  Created by Takeshi Hashimoto on 2026-02-12.
//

import SwiftUI
import UIKit

@main
struct LifeCastApp: App {
    init() {
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = LifeCastAPIClient.handleOAuthCallback(url: url)
                }
        }
    }

    private func configureTabBarAppearance() {
        UITabBar.appearance().isHidden = true

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.shadowColor = UIColor(white: 1.0, alpha: 0.14)

        let layouts = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for layout in layouts {
            layout.normal.iconColor = UIColor(white: 0.68, alpha: 1.0)
            layout.selected.iconColor = .white
            layout.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor.clear]
            layout.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 12)
            layout.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 12)
        }

        UITabBar.appearance().isTranslucent = false
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
