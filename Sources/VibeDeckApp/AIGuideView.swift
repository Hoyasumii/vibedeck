import SwiftUI

struct AIGuideView: View {
    @Environment(\.logProject) private var logProject
    @State private var section = -1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Assunto", selection: $section.logging(control: "aiguide_view.selection_2", label: "Assunto", project: logProject)) {
                    Text("Guia inicial").tag(-1)
                    ForEach(AgentsGuide.sections.indices, id: \.self) { index in
                        Text(String(AgentsGuide.sections[index].components(separatedBy: "\n")[0].dropFirst(3))).tag(index)
                    }
                }
                LoggedButton("Fechar") { dismiss() }.loggedControl(control: "aiguide_view.button_1", label: "Fechar")
            }
            ScrollView {
                Text(AgentsGuide.section(section) ?? AgentsGuide.markdown)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding().frame(minWidth: 600, minHeight: 400)
    }
}
