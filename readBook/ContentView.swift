//
//  ContentView.swift
//  readBook
//
//  Created by ext.cuixuecheng1 on 2026/6/16.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        BookShelfView()
    }
}

#Preview {
    ContentView()
        .environment(BookStore())
}
