//
//  ContentView.swift
//  Pocket Snes
//
//  The app's root: the library, the settings it shares, and the player that
//  appears whenever a game is running.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var library = GameLibrary()
    @StateObject private var settings = AppSettings()
    @StateObject private var session = PlaySession()

    var body: some View {
        LibraryView()
            .environmentObject(library)
            .environmentObject(settings)
            .environmentObject(session)
            .tint(Theme.Palette.accent)
            .preferredColorScheme(.dark)
            .fullScreenCover(item: $session.game) { game in
                PlayerView(game: game)
                    .environmentObject(library)
                    .environmentObject(settings)
                    .environmentObject(session)
            }
    }
}

#Preview {
    ContentView()
}
