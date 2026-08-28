import SwiftUI
import DeckCore
import DeckProgression

/// Settings.
///
/// The one place in the app where usability beats art direction outright: plain
/// grouped lists, native controls, everything where people expect it. The only
/// concession to the rest of the app is the type on the section headers.
public struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    @State private var settings = SettingsState()
    @State private var notificationPermission: NotificationService.Permission = .notDetermined
    @State private var showsResetConfirmation = false
    @State private var hasLoaded = false

    public init() {}

    public var body: some View {
        List {
            gameplaySection
            feedbackSection
            accessibilitySection
            dailySection
            accountSection
            aboutSection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { load() }
        .onChange(of: settings) { _, newValue in
            deck.progress.update(settings: newValue)
            deck.applyPreferences()
        }
        .confirmationDialog(String(localized: "settings.resetConfirm",
                                   defaultValue: "Erase all progress?"),
                            isPresented: $showsResetConfirmation,
                            titleVisibility: .visible) {
            Button(String(localized: "settings.resetConfirmAction", defaultValue: "Erase everything"),
                   role: .destructive) {
                deck.progress.resetAll()
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.resetMessage",
                        defaultValue: "Statistics, achievements, your streak and your collection will all go. This cannot be undone."))
        }
    }

    // MARK: - Sections

    private var gameplaySection: some View {
        Section {
            Toggle(String(localized: "settings.moveAssist", defaultValue: "Show playable cards"),
                   isOn: $settings.showMoveAssist)
            Toggle(String(localized: "settings.hintsInChallenges",
                          defaultValue: "Allow hints in the daily challenge"),
                   isOn: $settings.allowHintsInChallenges)
            Picker(String(localized: "settings.difficulty", defaultValue: "Default opponents"),
                   selection: $settings.preferredDifficulty) {
                ForEach(AIDifficulty.allCases, id: \.self) { value in
                    Text(CalloutRow.humanised(value.localizationKey)).tag(value)
                }
            }
        } header: {
            Text(String(localized: "settings.gameplay", defaultValue: "Gameplay"))
        } footer: {
            Text(String(localized: "settings.hintsFooter",
                        defaultValue: "Hints explain the rule behind a move. They are off in challenges by default so scores stay comparable."))
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle(String(localized: "settings.sound", defaultValue: "Sound"),
                   isOn: $settings.soundEnabled)
            Toggle(String(localized: "settings.haptics", defaultValue: "Haptics"),
                   isOn: $settings.hapticsEnabled)
        } header: {
            Text(String(localized: "settings.feedback", defaultValue: "Sound and feel"))
        }
    }

    private var accessibilitySection: some View {
        Section {
            Toggle(String(localized: "settings.reduceMotion", defaultValue: "Reduce motion"),
                   isOn: $settings.reduceMotion)
        } header: {
            Text(String(localized: "settings.accessibility", defaultValue: "Accessibility"))
        } footer: {
            Text(String(localized: "settings.reduceMotionFooter",
                        defaultValue: "Card physics and screen transitions are replaced with simple fades. Pass & Play still asks each player to confirm before their hand is shown."))
        }
    }

    private var dailySection: some View {
        Section {
            Toggle(String(localized: "settings.reminder", defaultValue: "Daily reminder"),
                   isOn: $settings.dailyReminderEnabled)
                .onChange(of: settings.dailyReminderEnabled) { _, isOn in
                    Task { await updateReminder(isOn: isOn) }
                }
            if settings.dailyReminderEnabled {
                DatePicker(String(localized: "settings.reminderTime", defaultValue: "Remind me at"),
                           selection: reminderTimeBinding,
                           displayedComponents: .hourAndMinute)
            }
            if notificationPermission == .denied {
                Text(String(localized: "settings.notificationsDenied",
                            defaultValue: "Notifications are turned off for DECK in the Settings app."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "settings.daily", defaultValue: "Daily challenge"))
        }
    }

    private var accountSection: some View {
        Section {
            if deck.progress.hasPremium {
                HStack {
                    Text(String(localized: "settings.premium", defaultValue: "Premium"))
                    Spacer()
                    Text(String(localized: "settings.premiumActive", defaultValue: "Active"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(String(localized: "settings.getPremium", defaultValue: "Get Premium")) {
                    router.push(.premium)
                }
            }
            Button(String(localized: "settings.restore", defaultValue: "Restore purchases")) {
                Task { await deck.store.restore() }
            }
            HStack {
                Text(String(localized: "settings.gameCenter", defaultValue: "Game Center"))
                Spacer()
                Text(deck.gameServices.isAuthenticated
                     ? (deck.gameServices.playerName
                        ?? String(localized: "gamecenter.connected", defaultValue: "Connected"))
                     : String(localized: "gamecenter.notConnected", defaultValue: "Not signed in"))
                    .foregroundStyle(.secondary)
            }
            if !deck.gameServices.isAuthenticated {
                Button(String(localized: "settings.connectGameCenter",
                              defaultValue: "Connect Game Center")) {
                    Task { await deck.gameServices.authenticate() }
                }
            }
        } header: {
            Text(String(localized: "settings.account", defaultValue: "Account"))
        } footer: {
            if let message = deck.gameServices.statusMessage {
                Text(message)
            } else {
                Text(String(localized: "settings.offlineFooter",
                            defaultValue: "Everything except leaderboards works with no connection at all."))
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text(String(localized: "settings.version", defaultValue: "Version"))
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "settings.games", defaultValue: "Games"))
                Spacer()
                Text("\(deck.registry.count)").foregroundStyle(.secondary)
            }
            if !deck.progress.loadFailures.isEmpty {
                // Being honest about a failed load is better than silently
                // starting from zero and letting somebody discover it later.
                Text(String(format: String(localized: "settings.loadFailures",
                                           defaultValue: "%d saved files could not be read and were reset."),
                            deck.progress.loadFailures.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #if DEBUG
            NavigationLink(String(localized: "settings.debug", defaultValue: "Developer tools")) {
                DebugMenu()
            }
            #endif
        } header: {
            Text(String(localized: "settings.about", defaultValue: "About"))
        }
    }

    private var dangerSection: some View {
        Section {
            Button(String(localized: "settings.reset", defaultValue: "Erase all progress"),
                   role: .destructive) {
                showsResetConfirmation = true
            }
        }
    }

    // MARK: - Helpers

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.dailyReminderMinutes / 60
                components.minute = settings.dailyReminderMinutes % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.dailyReminderMinutes = (components.hour ?? 19) * 60 + (components.minute ?? 0)
                Task { await updateReminder(isOn: settings.dailyReminderEnabled) }
            }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        settings = deck.progress.settings
        Task { notificationPermission = await NotificationService.shared.permission() }
    }

    private func updateReminder(isOn: Bool) async {
        guard isOn else {
            NotificationService.shared.cancelDailyReminder()
            return
        }
        if await NotificationService.shared.permission() == .notDetermined {
            _ = await NotificationService.shared.requestPermission()
        }
        notificationPermission = await NotificationService.shared.permission()
        guard notificationPermission == .granted else {
            settings.dailyReminderEnabled = false
            return
        }
        await NotificationService.shared.scheduleDailyReminder(
            atMinutesPastMidnight: settings.dailyReminderMinutes,
            streak: deck.progress.challenge.currentStreak)
    }
}

/// Local player profiles.
///
/// No accounts, no sign-in, no server. A family gets a name and a face each so
/// Pass & Play can keep score, and it all stays on the phone.
public struct ProfilesScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    @State private var newName = ""
    @State private var editing: PlayerProfile?

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(deck.progress.profiles.profiles) { profile in
                    HStack(spacing: DeckSpace.s) {
                        AvatarArt(avatarID: profile.avatarID, initials: profile.initials, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                                .font(DeckType.bodyEmphasis)
                            Text(String(format: String(localized: "profiles.record",
                                                       defaultValue: "%d played · %d won"),
                                        profile.gamesPlayed, profile.gamesWon))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.isPrimary {
                            Text(String(localized: "profiles.you", defaultValue: "You"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = profile }
                }
                .onDelete(perform: delete)
            } header: {
                Text(String(localized: "profiles.title", defaultValue: "Players on this device"))
            } footer: {
                Text(String(localized: "profiles.footer",
                            defaultValue: "Profiles are stored on this device only. There is no account and nothing is uploaded."))
            }

            Section {
                HStack {
                    TextField(String(localized: "profiles.newName", defaultValue: "Name"),
                              text: $newName)
                    Button(String(localized: "profiles.add", defaultValue: "Add")) { add() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(String(localized: "profiles.title", defaultValue: "Players"))
        .sheet(item: $editing) { profile in
            ProfileEditor(profile: profile) { updated in
                var profiles = deck.progress.profiles
                profiles.upsert(updated)
                deck.progress.update(profiles: profiles)
                editing = nil
            }
        }
    }

    private func add() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var profiles = deck.progress.profiles
        profiles.upsert(PlayerProfile(name: trimmed,
                                      isPrimary: profiles.profiles.isEmpty))
        deck.progress.update(profiles: profiles)
        newName = ""
        Haptics.shared.tap(.place)
    }

    private func delete(at offsets: IndexSet) {
        var profiles = deck.progress.profiles
        for index in offsets {
            let profile = profiles.profiles[index]
            guard !profile.isPrimary else { continue }
            profiles.remove(profile.id)
        }
        deck.progress.update(profiles: profiles)
    }
}

/// Renaming a player and choosing their mark.
public struct ProfileEditor: View {
    @State private var draft: PlayerProfile
    private let onSave: (PlayerProfile) -> Void

    @Environment(AppEnvironment.self) private var deck
    @Environment(\.dismiss) private var dismiss

    public init(profile: PlayerProfile, onSave: @escaping (PlayerProfile) -> Void) {
        self._draft = State(initialValue: profile)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "profiles.newName", defaultValue: "Name"),
                              text: $draft.name)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: DeckSpace.s)],
                              spacing: DeckSpace.s) {
                        ForEach(availableAvatars, id: \.id) { cosmetic in
                            Button {
                                draft.avatarID = cosmetic.id
                            } label: {
                                AvatarArt(avatarID: cosmetic.id, initials: draft.initials, size: 52)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(draft.avatarID == cosmetic.id
                                                          ? DeckPalette.vermilion : .clear,
                                                          lineWidth: 3)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(cosmetic.englishName))
                        }
                    }
                } header: {
                    Text(String(localized: "profiles.avatar", defaultValue: "Mark"))
                }
            }
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save", defaultValue: "Save")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var availableAvatars: [Cosmetic] {
        CosmeticCatalog.items(of: .avatar).filter { deck.progress.collection.owns($0.id) }
    }
}
