import SwiftUI
import VibeDeckCore

private struct LogProjectKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}
extension EnvironmentValues {
    var logProject: URL? {
        get { self[LogProjectKey.self] }
        set { self[LogProjectKey.self] = newValue }
    }
}

/// Explicit ids live at the call site, so translating or changing a label preserves identity.
struct LoggedButton<LabelView: View>: View {
    @Environment(\.logProject) private var project
    @FocusedValue(\.logProjectRoot) private var focusedProject
    var control: String
    var logLabel: String
    let role: ButtonRole?
    let action: () -> Void
    let label: LabelView

    init(control: String = "", logLabel: String = "", role: ButtonRole? = nil, action: @escaping () -> Void,
         @ViewBuilder label: () -> LabelView) {
        self.control = control; self.logLabel = logLabel; self.role = role
        self.action = action; self.label = label()
    }

    func loggedControl(control: String, label: String) -> Self {
        var copy = self; copy.control = control
        // Text titles supply the visible label; icon-only controls use the call-site label.
        if copy.logLabel.isEmpty { copy.logLabel = label }
        return copy
    }

    var body: some View {
        Button(role: role) {
            VDLog.withAction(control: control, label: logLabel, project: project ?? focusedProject, action)
        } label: { label }
    }
}
extension LoggedButton where LabelView == Text {
    init(control: String = "", logLabel: String = "", _ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(control: control, logLabel: title.isEmpty ? logLabel : title, role: role, action: action) { Text(title) }
    }
}
extension LoggedButton where LabelView == Label<Text, Image> {
    init(control: String = "", logLabel: String = "", _ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(control: control, logLabel: title, role: role, action: action) { Label(title, systemImage: systemImage) }
    }
}

extension Binding {
    /// Setter-only logging: rendering and programmatic state restoration don't create actions.
    func logging(control: String, label: String, project: URL? = nil) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { value in
            VDLog.withAction(control: control, label: label, project: project) { wrappedValue = value }
        })
    }
}

extension View {
    func onLoggedSubmit(control: String, label: String, action: @escaping () -> Void) -> some View {
        modifier(LoggedSubmit(control: control, label: label, action: action))
    }
}
private struct LoggedSubmit: ViewModifier {
    @Environment(\.logProject) private var project
    var control: String
    let label: String
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onSubmit { VDLog.withAction(control: control, label: label, project: project, action) }
    }
}

/// One editing session, one confirmation log. The binding never logs the text itself.
struct LoggedTextField: View {
    @Environment(\.logProject) private var project
    @FocusState private var focused: Bool
    @State private var editingAction: String?
    @Binding var text: String
    var control: String
    var logLabel: String
    let title: String
    var prompt: Text?
    var axis: Axis
    var onCommit: (() -> Void)?

    init(control: String = "", logLabel: String = "", _ title: String, text: Binding<String>, prompt: Text? = nil,
         axis: Axis = .horizontal, onCommit: (() -> Void)? = nil) {
        self.control = control; self.logLabel = logLabel; self.title = title
        _text = text; self.prompt = prompt; self.axis = axis; self.onCommit = onCommit
    }

    func loggedField(control: String, label: String) -> Self {
        var copy = self; copy.control = control; copy.logLabel = label
        return copy
    }

    var body: some View {
        TextField(title, text: Binding(get: { text }, set: { value in
            guard value != text else { return }
            let id = editingAction ?? UUID().uuidString
            editingAction = id
            VDLog.$actionID.withValue(id) {
                VDLog.$projectRoot.withValue(project) { text = value }
            }
        }), prompt: prompt, axis: axis)
        .focused($focused)
        .onSubmit { confirm(submitting: true) }
        .onChange(of: focused) { _, value in if !value { confirm(submitting: false) } }
    }

    private func confirm(submitting: Bool) {
        guard let id = editingAction else { return }
        editingAction = nil
        VDLog.withAction(control: control, label: logLabel, project: project, id: id) { if submitting { onCommit?() } }
    }
}

/// The projected binding logs user selection; assigning the value to restore navigation stays silent.
@propertyWrapper struct LoggedSelection<Value>: DynamicProperty {
    @Environment(\.logProject) private var project
    @State private var value: Value
    let control: String
    let label: String
    init(wrappedValue: Value, control: String, label: String) {
        _value = State(initialValue: wrappedValue); self.control = control; self.label = label
    }
    var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue }
    }
    var projectedValue: Binding<Value> {
        $value.logging(control: control, label: label, project: project)
    }
}

// Metadata is separate from the proposal's reviewed product copy.
enum LogControls {
    static let docsGenerate = "docs.generate"
    static let docGenerateButton1 = "doc_generate.button_1"
    static let docGenerateButton2 = "doc_generate.button_2"
    static let docGenerateButton3 = "doc_generate.button_3"
    static let docGenerateButton4 = "doc_generate.button_4"
    static let docGenerateButton5 = "doc_generate.button_5"
    static let docGenerateLabel1 = "Pré-visualizar"
    static let docGenerateLabel2 = "Descartar"
    static let docGenerateLabel3 = "Cancelar"
    static let docGenerateLabel4 = "Aceitar selecionados"
    static let docGenerateLabel5 = "Aceitar todos"
    static let docGenerateTitle = "docgenerate.text_1"
    static let docGenerateSelection = "doc_generate.selection_6"
}
