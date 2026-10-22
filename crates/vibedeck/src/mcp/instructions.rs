//! Texto das `instructions` do initialize (fiel a MCPServer.swift L172-189).

pub fn instructions(root: &str) -> String {
    format!(
        "Projeto VibeDeck em {root}.\n\
\n\
REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras.\n\
Antes de dizer que terminou qualquer alteração:\n\
1. chame rules_for com os arquivos que você alterou (e review_item, se houver);\n\
2. chame submit_rule_check (results=[]): ele roda os scripts das regras sozinho; as manuais ficam pending;\n\
3. se passed=false, corrija e envie outro check. Só conclua com passed=true, avisando os warnings\n   \
(\"should\") e quantas manuais ficaram sem verificar;\n\
4. manuais só quando o usuário pedir: rules_for include_manual=true e submit_rule_check\n   \
verify_manual=true respondendo pass/fail/na para TODAS, com evidência.\n\
Antes de implementar: itens de revisão abertos da área, list_stack e list_patterns. Registros criados por você são author=ai.\n\
Ideias que surgirem: add_idea (não são regras ativas).\n\
Referências aceitam slug, id (ou prefixo >= 4) ou título.\n\
Guia: .vibedeck/AGENTS.md (leia antes). Detalhes: ai_guide."
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn respeita_orcamento_e_marcadores() {
        let t = instructions("/x");
        assert!(t.chars().count() <= 1200);
        assert!(!t.contains("Trabalhe por escopo"));
        for m in ["rules_for", "submit_rule_check", "passed=true", "verify_manual", "AGENTS.md"] {
            assert!(t.contains(m), "{m}");
        }
        assert!(t.starts_with("Projeto VibeDeck em /x.\n\nREGRA"));
        assert!(t.ends_with("Detalhes: ai_guide."));
        assert!(t.contains("avisando os warnings\n   (\"should\")"));
    }
}
