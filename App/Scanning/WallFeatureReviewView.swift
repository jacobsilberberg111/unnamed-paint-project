import ScanCore
import SwiftUI
import UIKit

/// After the scan: the few things the camera spotted on the walls but couldn't be sure
/// about. Each has a photo, its size and a best guess; one tap to confirm or change.
struct WallFeatureReviewView: View {
    let items: [WallFeatureSuggestion]
    let autoAdded: Int
    /// Chosen kind per item; nil means leave the wall as it is.
    let onDone: ([UUID: SurfaceKind?]) -> Void

    @State private var choices: [UUID: Choice]

    enum Choice: Hashable, CaseIterable {
        case window, door, noPaint, ignore

        var title: String {
            switch self {
            case .window: return "Window"
            case .door: return "Door"
            case .noPaint: return "Don't paint"
            case .ignore: return "Ignore"
            }
        }

        var kind: SurfaceKind? {
            switch self {
            case .window: return .window
            case .door: return .door
            case .noPaint: return .noPaint
            case .ignore: return nil
            }
        }

        init(_ kind: SurfaceKind?) {
            switch kind {
            case .window?: self = .window
            case .door?: self = .door
            case .noPaint?: self = .noPaint
            default: self = .ignore
            }
        }
    }

    init(items: [WallFeatureSuggestion], autoAdded: Int, onDone: @escaping ([UUID: SurfaceKind?]) -> Void) {
        self.items = items
        self.autoAdded = autoAdded
        self.onDone = onDone
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: items.map { ($0.id, Choice($0.verdict.kind)) }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick check")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                        ForEach(items) { item in
                            card(item)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 100)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(BackdropView())
            .safeAreaInset(edge: .bottom) {
                Button {
                    onDone(choices.mapValues(\.kind))
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(GradientButtonStyle())
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private var subtitle: String {
        let auto = autoAdded == 0 ? "" : "\(autoAdded) thing\(autoAdded == 1 ? " was" : "s were") added automatically. "
        return auto + "The camera also spotted \(items.count == 1 ? "this" : "these") on the walls but wasn't sure what \(items.count == 1 ? "it is" : "they are")."
    }

    private func card(_ item: WallFeatureSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.3))
                if let data = item.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(8)
                } else {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 180)

            HStack {
                Text(Units.size(item.width, item.height))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Text(item.wallLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.verdict.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("What is it?", selection: Binding(
                get: { choices[item.id] ?? .ignore },
                set: { choices[item.id] = $0 }
            )) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
        .card(padding: 14)
    }
}
