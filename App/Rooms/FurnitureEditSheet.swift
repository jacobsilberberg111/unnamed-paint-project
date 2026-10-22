import ScanCore
import SwiftUI

/// Paint a piece of furniture or not, and optionally enter its measured area.
struct FurnitureEditSheet: View {
    let item: FurnitureItem
    /// Include it, and the measured area (nil keeps the estimate).
    let onSave: (Bool, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var include: Bool
    @State private var area: Double

    init(item: FurnitureItem, onSave: @escaping (Bool, Double?) -> Void) {
        self.item = item
        self.onSave = onSave
        _include = State(initialValue: item.isPainted)
        _area = State(initialValue: item.paintAreaM2)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Paint this", isOn: $include)
                }

                Section {
                    HStack {
                        Text("Paintable area (m²)")
                        Spacer()
                        TextField("Area", value: $area, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.monospacedDigit())
                            .frame(maxWidth: 120)
                    }
                    if item.isAreaMeasured {
                        Button("Use the estimate (\(Units.squareMetres(item.estimatedAreaM2)))") {
                            area = item.estimatedAreaM2
                        }
                    }
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(item.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let measured = abs(area - item.estimatedAreaM2) >= 0.005 ? area : nil
                        onSave(include, measured)
                        dismiss()
                    }
                    .disabled(area < 0)
                }
            }
        }
    }

    private var footer: String {
        let against = item.facesAgainstWall == 0 ? "" :
            " \(item.facesAgainstWall) side\(item.facesAgainstWall == 1 ? " is" : "s are") against a wall and left out."
        return "Estimated \(Units.squareMetres(item.estimatedAreaM2)) from its outline: front, exposed sides and top.\(against) Open pieces like desks have less surface than their outline, so measure if it matters."
    }
}
