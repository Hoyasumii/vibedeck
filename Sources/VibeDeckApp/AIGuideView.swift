import SwiftUI
import VibeDeckCore

struct AIGuideView: View {
    @State private var section = -1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Assunto", selection: $section) {
                    Text("Guia inicial").tag(-1)
                    ForEach(AgentsGuide.sections.indices, id: \.self) { index in
                        Text(String(AgentsGuide.sections[index].components(separatedBy: "\n")[0].dropFirst(3))).tag(index)
                    }
                }
                Button("Fechar") { dismiss() }
            }
            ScrollView {
                Text(AgentsGuide.section(section) ?? AgentsGuide.markdown)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding().frame(minWidth: 600, minHeight: 400)
    }
}
