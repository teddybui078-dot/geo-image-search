import SwiftUI

// Shown as a sheet before the first sync (and again from "Change range" in
// ContentView's sync bar) so the user picks how far back to sync instead of
// always processing the whole library.
struct SyncRangePickerView: View {
    let onSelect: (SyncDateRangeOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How far back should photos be synced?")
                .font(.headline)
            Text("You can change this later from the sync bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(SyncDateRangeOption.allCases, id: \.self) { option in
                    Button(option.displayName) {
                        onSelect(option)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .frame(minWidth: 320)
    }
}
