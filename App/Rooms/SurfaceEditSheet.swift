import ScanCore
import SwiftUI

/// Correct one wall, door or window: tape measurement, what it really is, or remove
/// it as a false detection.
struct SurfaceEditSheet: View {
    let surface: Surface
    /// What RoomPlan originally called it, before any type fix.
    let originalKind: SurfaceKind
    let existing: SurfaceOverride?
    let onSave: (SurfaceOverride?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width: Double
    @State private var height: Double
    @State private var kind: SurfaceKind

    private var isOpening: Bool { [.door, .window, .opening, .noPaint].contains(surface.kind) }

    init(surface: Surface, originalKind: SurfaceKind, existing: SurfaceOverride?, onSave: @escaping (SurfaceOverride?) -> Void) {
        self.surface = surface
        self.originalKind = originalKind
        self.existing = existing
        self.onSave = onSave
        _width = State(initialValue: surface.widthM)
        _height = State(initialValue: surface.heightM)
        _kind = State(initialValue: surface.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isOpening {
                    Section {
                        Picker("This is a", selection: $kind) {
                            Text("Door").tag(SurfaceKind.door)
                            Text("Window").tag(SurfaceKind.window)
                            Text("Opening").tag(SurfaceKind.opening)
                            Text("Don't paint").tag(SurfaceKind.noPaint)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("What is it?")
                    } footer: {
                        if surface.flags.contains(.nearFurniture) {
                            Text("There's furniture in front of this. Clutter is the most common cause of false detections, so check it's really there.")
                        }
                    }
                }

                Section {
                    measurementField("Width", value: $width, lidar: surface.scannedWidthM)
                    measurementField("Height", value: $height, lidar: surface.scannedHeightM)
                } header: {
                    Text("Tape measurement (metres)")
                } footer: {
                    Text("LiDAR measured \(Units.size(surface.scannedWidthM, surface.scannedHeightM)). Enter what your tape says; everything that depends on this surface is recalculated.")
                }

                Section {
                    if existing?.widthM != nil || existing?.heightM != nil {
                        Button("Use the LiDAR measurement") {
                            var o = existing ?? SurfaceOverride(surfaceId: surface.id)
                            o.widthM = nil
                            o.heightM = nil
                            onSave(o)
                            dismiss()
                        }
                    }
                    Button(isOpening ? "Not really there: remove it" : "Not a real wall: remove it", role: .destructive) {
                        onSave(SurfaceOverride(surfaceId: surface.id, removed: true))
                        dismiss()
                    }
                } footer: {
                    Text("Removed items are left out of every measurement. You can put them back from the room screen.")
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

    /// Only keep what actually differs from the scan.
    private func makeOverride() -> SurfaceOverride? {
        var o = SurfaceOverride(surfaceId: surface.id)
        o.widthM = abs(width - surface.scannedWidthM) >= 0.0005 ? width : nil
        o.heightM = abs(height - surface.scannedHeightM) >= 0.0005 ? height : nil
        // Compared with the original detection, so switching back clears the fix.
        o.kind = isOpening && kind != originalKind ? kind : nil
        return o.isEmpty ? nil : o
    }
}
