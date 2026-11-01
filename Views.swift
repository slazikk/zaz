import SwiftUI

struct TokenSignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var token = ""
    @State private var working = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 72)).foregroundStyle(.orange)
                Text("Zvuk Music").font(.largeTitle.bold())
                Text("Неофициальный клиент. Нужна активная подписка «Звук».").multilineTextAlignment(.center).foregroundStyle(.secondary)
                SecureField("X-Auth-Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button(working ? "Проверяем…" : "Войти") { working = true; Task { await session.signIn(token: token.trimmingCharacters(in: .whitespacesAndNewlines)); working = false } }
                    .buttonStyle(.borderedProminent).disabled(token.isEmpty || working)
                Text("Откройте zvuk.com/api/tiny/profile в браузере после входа и скопируйте поле token.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(28).navigationTitle("Авторизация")
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            SearchView().tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Медиатека", systemImage: "books.vertical") }
            SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }
        }.safeAreaInset(edge: .bottom) { MiniPlayer() }
    }
}

struct SearchView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var text = ""
    @State private var results: [SearchItem] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { ContentUnavailableView("Не удалось выполнить поиск", systemImage: "wifi.exclamationmark", description: Text(error)) }
                ForEach(results) { item in
                    Button { if case let .track(track) = item { Task { await player.play(track) } } } label: { SearchRow(item: item) }.buttonStyle(.plain)
                }
            }.navigationTitle("Поиск")
                .searchable(text: $text, prompt: "Трек, артист, альбом или плейлист")
                .onChange(of: text) { _, value in scheduleSearch(value) }
        }
    }
    private func scheduleSearch(_ value: String) {
        guard value.trimmingCharacters(in: .whitespaces).count > 1 else { results = []; return }
        loading = true; error = nil
        Task { try? await Task.sleep(for: .milliseconds(350)); guard text == value else { return }
            do { results = try await ZvukAPI.shared.quickSearch(value) } catch { self.error = error.localizedDescription }; loading = false
        }
    }
}

struct SearchRow: View {
    let item: SearchItem
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artwork).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) { Text(item.title).lineLimit(1); Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(); if case .track = item { Image(systemName: "play.circle").foregroundStyle(.orange) }
        }.contentShape(Rectangle())
    }
    private var artwork: URL? { switch item { case .track(let x): x.artworkURL; case .artist(let x): x.image?.src.flatMap(URL.init(string:)); case .release(let x): x.image?.src.flatMap(URL.init(string:)); case .playlist(let x): x.image?.src.flatMap(URL.init(string:)) } }
}

struct ArtworkView: View {
    let url: URL?
    var body: some View { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }.clipShape(RoundedRectangle(cornerRadius: 8)) }
}

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var loading = false
    @State private var error: String?
    @State private var newPlaylistName = ""
    @State private var showingCreate = false
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.red) }
                Section("Мои плейлисты") {
                    ForEach(playlists) { playlist in SearchRow(item: .playlist(playlist)) }
                    Button { showingCreate = true } label: { Label("Создать плейлист", systemImage: "plus") }
                }
                Section("Любимые треки") {
                    ForEach(tracks) { track in Button { Task { await player.play(track) } } label: { SearchRow(item: .track(track)) }.buttonStyle(.plain) }
                }
            }.navigationTitle("Медиатека").refreshable { await load() }.task { await load() }
                .alert("Новый плейлист", isPresented: $showingCreate) { TextField("Название", text: $newPlaylistName); Button("Создать") { Task { await createPlaylist() } }; Button("Отмена", role: .cancel) {} }
        }
    }
    private func load() async { loading = true; error = nil; do { async let t = ZvukAPI.shared.libraryTracks(); async let p = ZvukAPI.shared.playlists(); tracks = try await t; playlists = try await p } catch { self.error = error.localizedDescription }; loading = false }
    private func createPlaylist() async { guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }; do { try await ZvukAPI.shared.createPlaylist(name: newPlaylistName); newPlaylistName = ""; await load() } catch { self.error = error.localizedDescription } }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View { NavigationStack { Form { Section("Аккаунт") { Text("Токен хранится в Keychain устройства").font(.footnote); Button("Выйти", role: .destructive) { session.signOut() } } Section("О приложении") { Text("Неофициальный клиент для сервиса Звук.").font(.footnote) } }.navigationTitle("Настройки") } }
}

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    var body: some View { if let track = player.current { VStack(spacing: 3) { ProgressView(value: player.progress, total: max(player.duration, 1)).tint(.orange); HStack { ArtworkView(url: track.artworkURL).frame(width: 40, height: 40); VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.artistText).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2) }.buttonStyle(.plain) }.padding(.horizontal).padding(.bottom, 4) }.background(.bar) } }
}
