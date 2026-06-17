//
//  readBookApp.swift
//  readBook
//
//  Created by ext.cuixuecheng1 on 2026/6/16.
//

import SwiftUI

@main
struct readBookApp: App {
    @State private var store = BookStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onOpenURL { url in
                    store.importBooks(from: [url])
                }
        }
    }
}
