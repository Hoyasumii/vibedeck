import SwiftUI

/// Contexto do item no detalhe (regra 34D2EA32): regras da ideia, verificações do tópico, painel do ponto de revisão,
/// fluxo do agente/comando/skill/workflow. Fica ao lado do conteúdo, dentro da coluna de detalhe, e não num
/// inspector separado: a coluna da direita da janela é só o painel de IA (⇧⌘C). ⌥⌘I mostra/oculta o contexto.
struct V2DetailContext<Context: View>: ViewModifier {
    @Binding var isPresented: Bool
    let context: Context

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            if isPresented {
                Divider()
                context
                    .frame(width: DesignTokens.V2Layout.contextWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

extension View {
    /// Mostra o contexto do item ao lado do detalhe quando `isPresented`.
    func detailContext<Context: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Context) -> some View {
        modifier(V2DetailContext(isPresented: isPresented, context: content()))
    }
}
