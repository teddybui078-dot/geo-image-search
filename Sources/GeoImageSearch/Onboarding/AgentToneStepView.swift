import SwiftUI

struct AgentToneStepView: View {
    let onNext: (AgentTone) -> Void

    // Preselected default — this step is never blocking, so no Skip button.
    @State private var selectedTone: AgentTone = .warm

    var body: some View {
        VStack(spacing: 16) {
            Text("How should the agent talk to you?")
                .font(.title2.bold())
            Picker("Tone", selection: $selectedTone) {
                ForEach(AgentTone.allCases, id: \.self) { tone in
                    Text(tone.displayName).tag(tone)
                }
            }
            .pickerStyle(.radioGroup)
            .frame(maxWidth: 320)
            Button("Continue") { onNext(selectedTone) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
