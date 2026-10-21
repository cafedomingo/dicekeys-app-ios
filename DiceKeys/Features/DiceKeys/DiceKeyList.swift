//
//  DiceKeyList.swift
//  DiceKeys
//

import SwiftData
import SwiftUI

/// Home: every DiceKey the app has seen with its keys beneath, so a key is one tap away. Before
/// the first DiceKey, the one way in.
struct DiceKeyList: View {
    @Binding var selection: SidebarSelection?
    let onScan: () -> Void
    let onDelete: (KeyEntry) -> Void

    @Query(sort: \DiceKeyRecord.name) private var records: [DiceKeyRecord]
    @Query(sort: [SortDescriptor(\KeyEntry.name), SortDescriptor(\KeyEntry.created)]) private var entries: [KeyEntry]
    @Environment(UnlockedDiceKeys.self) private var unlocked
    @State private var keyToDelete: KeyEntry?
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if records.isEmpty {
                FirstDiceKey(onScan: onScan)
            } else {
                List(selection: $selection) {
                    ForEach(records.uniqueDiceKeys) { record in
                        section(for: record)
                    }
                }
                .navigationTitle(AppInfo.name)
                .confirmsKeyDeletion($keyToDelete, onDelete: onDelete)
            }
        }
        .appBackdrop()
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan DiceKey", systemImage: "camera.viewfinder", action: onScan)
                }
            }
            ToolbarItem {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }

    private func section(for record: DiceKeyRecord) -> some View {
        let keys = entries.filter { $0.diceKeyID == record.diceKeyID }.uniqueKeys
        return Section {
            DiceKeyRow(record: record, keyCount: keys.count)
                .tag(SidebarSelection.diceKey(record.diceKeyID))
            ForEach(keys) { entry in
                KeyRow(entry: entry)
                    .tag(SidebarSelection.key(entry.persistentModelID))
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash") { keyToDelete = entry }
                            .tint(Color.danger)
                    }
            }
            if unlocked.diceKey(id: record.diceKeyID) != nil {
                Label("New key", systemImage: "plus")
                    .foregroundStyle(.tint)
                    .tag(SidebarSelection.newKey(record.diceKeyID))
            }
        }
    }
}

/// A DiceKey on home: its center die, ringed while unlocked, and how to unlock it here when
/// it is kept on this device. The separator starts under the name, not the Unlock button,
/// which a list would otherwise take as the row's text.
private struct DiceKeyRow: View {
    private static let lineSpacing: CGFloat = 2

    let record: DiceKeyRecord
    let keyCount: Int

    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved

    var body: some View {
        let isUnlocked = unlocked.diceKey(id: record.diceKeyID) != nil
        let locksAt = unlocked.locksAt(id: record.diceKeyID)
        HStack(spacing: .space3) {
            RingedAvatar(centerFace: record.centerFace, locksAt: locksAt, isUnlocked: isUnlocked)
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                Text(record.name).font(.headline)
                status(isUnlocked: isUnlocked, locksAt: locksAt).font(.subheadline)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer()
            if !isUnlocked && saved.contains(id: record.diceKeyID) {
                UnlockButton(diceKeyID: record.diceKeyID, name: record.name)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
    }

    private func status(isUnlocked: Bool, locksAt: Date?) -> Text {
        if let locksAt {
            return Text("Locks in \(Text(timerInterval: Date.now...max(.now, locksAt), countsDown: true))")
                .foregroundStyle(Color.accentInk)
        }
        let keys = keyCount == 0 ? Text("no keys yet") : Text("^[\(keyCount) key](inflect: true)")
        return Text("\(isUnlocked ? "Unlocked" : "Locked") · \(keys)").foregroundStyle(.secondary)
    }
}

/// A DiceKey's center die, ringed while it is unlocked, the ring draining as the countdown to
/// locking runs out. Space for the ring is kept while locked, so the row doesn't move.
private struct RingedAvatar: View {
    private static let dieSize = DieView.Size.header
    private static let width: CGFloat = 3
    private static let gap: CGFloat = 3
    /// Seconds between steps of the ring when Reduce Motion is on.
    private static let reducedMotionStep: Double = 1

    let centerFace: String
    let locksAt: Date?
    let isUnlocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let inset = Self.gap + Self.width
        DiceAvatar(centerFace: centerFace, size: Self.dieSize)
            .padding(inset)
            .overlay {
                if isUnlocked {
                    TimelineView(schedule) { context in
                        RoundedRectangle(cornerRadius: DieView.spacing(for: Self.dieSize) + inset)
                            .inset(by: Self.width / 2)
                            .trim(from: 0, to: remaining(at: context.date))
                            .stroke(Color.accentInk, style: StrokeStyle(lineWidth: Self.width, lineCap: .round))
                    }
                }
            }
    }

    private var schedule: AnimationTimelineSchedule {
        .animation(minimumInterval: reduceMotion ? Self.reducedMotionStep : nil, paused: locksAt == nil)
    }

    private func remaining(at date: Date) -> CGFloat {
        guard let locksAt else { return 1 }
        return max(0, locksAt.timeIntervalSince(date)) / UnlockedDiceKeys.lockDelay
    }
}

/// Home before any DiceKey: what the app needs, and the button that starts.
private struct FirstDiceKey: View {
    private static let markSide: CGFloat = 112

    let onScan: () -> Void

    var body: some View {
        VStack(spacing: .space6) {
            Spacer()
            AppMark(side: Self.markSide)
            VStack(spacing: .space2) {
                Text(AppInfo.name).font(.largeTitle.bold())
                Text("Your keys come from your DiceKey. Scan its 25 dice to start.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: onScan) {
                Label("Scan your DiceKey", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.extraLarge)
            Text("Restoring from a list card or recovery sheet? Scan its code the same way.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
