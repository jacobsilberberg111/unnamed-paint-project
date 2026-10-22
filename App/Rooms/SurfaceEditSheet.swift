import ScanCore
import SwiftUI

/// Enter a tape measurement for one wall, door or window.
struct SurfaceEditSheet: View {
    let surface: Surface
    let onSave: (SizeOverride?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width: Double
    @State private var height: Double

    init(surface: Surface, onSave: @escaping (SizeOverride?) -> Void) {
        self.surface = surface
        self.onSave = onSave
        _width = State(initialValue: surface.widthM)
        _height = State(initialValue: surface.heightM)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    measurementField("Width", value: $width, lidar: surface.scannedWidthM)
                    measurementField("Height", value: $height, lidar: surface.scannedHeightM)
                } header: {
                    Text("Tape measurement (metres)")
                } footer: {
                    Text("LiDAR measured \(Units.size(surface.scannedWidthM, surface.scannedHeightM)). Enter what your tape says; everything that depends on this surface is recalculated.")
                }

                if surface.flags.contains(.tapeMeasured) {
                    Section {
                        Button("Use the LiDAR measurement", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(surface.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(makeOverride())
                        dismiss()
                    }
                    .disabled(width <= 0 || height <= 0)
                }
            }
        }
    }

    private func measurementField(_ title: String, value: Binding<Double>, lidar: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            if abs(value.wrappedValue - lidar) >= 0.0005 {
                Text(Units.centimetres(lidar - value.wrappedValue) + " vs LiDAR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.monospacedDigit())
                .frame(maxWidth: 140)
        }
    }

    /// Only keep dimensions that actually differ from the scan.
    private func makeOverride() -> SizeOverride? {
        let w = abs(width - surface.scannedWidthM) >= 0.0005 ? width : nil
        let h = abs(height - surface.scannedHeightM) >= 0.0005 ? height : nil
        let o = SizeOverride(surfaceId: surface.id, widthM: w, heightM: h)
        return o.isEmpty ? nil : o
    }
}
