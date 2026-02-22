import SwiftUI

struct TranscriptHistoryView: View {
    @ObservedObject private var store = TranscriptHistoryStore.shared
    @State private var searchText = ""

    private var filteredEntries: [TranscriptEntry] {
        if searchText.isEmpty {
            return store.entries
        }
        return store.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcripts…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            // Entry list or empty state
            if filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(store.entries.isEmpty ? "No transcripts yet" : "No matching transcripts")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(store.entries.isEmpty ? "Your dictation history will appear here." : "Try a different search term.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        TranscriptRowView(entry: entry)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.deleteEntry(filteredEntries[index])
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer
            HStack {
                Text("\(store.entries.count) transcript\(store.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.entries.isEmpty {
                    Button("Clear All") {
                        store.clearAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }
            .padding(10)
        }
        .frame(width: 400, height: 500)
    }
}

// MARK: - Row view

struct TranscriptRowView: View {
    let entry: TranscriptEntry
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack {
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(showCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
