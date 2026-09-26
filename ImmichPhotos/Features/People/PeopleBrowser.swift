import SwiftUI

struct PeopleBrowser: View {
    let client: ImmichClient
    let onSelect: (ImmichPerson) -> Void
    @State private var people: [ImmichPerson] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading People…")
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn’t Load People", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if people.isEmpty {
                ContentUnavailableView(
                    "No Named People",
                    systemImage: "person.2",
                    description: Text("Name people in Immich to browse their photos here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 24) {
                        ForEach(people) { person in
                            PersonTile(person: person, client: client) { onSelect(person) }
                        }
                    }
                    .padding(32)
                }
            }
        }
        .navigationTitle("People")
        .toolbar {
            Button { Task { await load() } } label: {
                Label("Refresh People", systemImage: "arrow.clockwise")
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { people = try await client.people() }
        catch { self.error = error.localizedDescription }
    }
}

private struct PersonTile: View {
    let person: ImmichPerson
    let client: ImmichClient
    let action: () -> Void
    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 10, y: 4)
                .scaleEffect(isHovering ? 1.03 : 1)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                Text(person.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let count = person.numberOfAssets {
                    Text("\(count) \(count == 1 ? "photo" : "photos")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.displayName)
        .onHover { isHovering = $0 }
        .task {
            guard image == nil else { return }
            if let data = try? await client.personThumbnail(id: person.id) {
                image = NSImage(data: data)
            }
        }
    }
}
