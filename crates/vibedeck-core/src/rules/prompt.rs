//! `RuleTestPrompt`: o prompt do botão "Gerar/Atualizar testes" (também usado em modo headless pela CLI).

use crate::model::{Rule, RuleTopic};

use super::rule::{RuleExt, RuleTestState, trimmed_non_empty};

/// Quais regras de um tópico uma geração cobre.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PromptSelection {
    /// Sem teste registrado.
    Missing,
    /// A regra mudou depois do teste.
    Stale,
    /// `Missing` + `Stale`.
    Pending,
    /// Todas, inclusive as de teste atual.
    All,
}

/// Onde vai o script gerado de uma regra, relativo à raiz do projeto.
pub fn script_path(topic_slug: &str, rule: &Rule) -> String {
    let id8: String = rule.id.to_string().to_lowercase().chars().take(8).collect();
    format!(".vibedeck/tests/{topic_slug}/{id8}.sh")
}

pub fn rules_for_selection(topic: &RuleTopic, selection: PromptSelection) -> Vec<&Rule> {
    topic
        .rules
        .iter()
        .filter(|r| match selection {
            PromptSelection::Missing => r.test_state() == RuleTestState::None,
            PromptSelection::Stale => r.test_state() == RuleTestState::Stale,
            PromptSelection::Pending => {
                matches!(r.test_state(), RuleTestState::None | RuleTestState::Stale)
            }
            PromptSelection::All => true,
        })
        .collect()
}

/// Prompt de geração dos testes de `selection`. `headless` (com o caminho do `cli`) é para um `claude -p`
/// em segundo plano: ninguém responde perguntas e os MCP do projeto podem não estar aprovados, então ele
/// registra pela CLI e termina com um resumo curto.
pub fn generate_prompt(
    slug: &str,
    topic: &RuleTopic,
    selection: PromptSelection,
    headless: Option<&str>,
) -> String {
    let rules = rules_for_selection(topic, selection);
    let list = rules
        .iter()
        .map(|rule| {
            let id8: String = rule.id.to_string().chars().take(8).collect();
            let mut line = format!("- `{id8}` [{}] {}", severity(rule), rule.text);
            if let Some(details) = rule.details.as_deref().and_then(trimmed_non_empty) {
                line.push('\n');
                line.push_str(
                    &details
                        .split('\n')
                        .map(|l| format!("  > {l}"))
                        .collect::<Vec<_>>()
                        .join("\n"),
                );
            }
            let test = rule.test.as_ref();
            match rule.test_state() {
                RuleTestState::Stale => line.push_str(&format!(
                    "\n  (a regra mudou desde o teste atual: `{}` — reescreva)",
                    test.and_then(|t| t.command.as_deref()).unwrap_or("manual")
                )),
                RuleTestState::Script => line.push_str(&format!(
                    "\n  (teste atual: `{}`)",
                    test.and_then(|t| t.command.as_deref()).unwrap_or("")
                )),
                RuleTestState::Manual => line.push_str(&format!(
                    "\n  (hoje manual: {})",
                    test.and_then(|t| t.reason.as_deref())
                        .unwrap_or("sem motivo")
                )),
                RuleTestState::None => {}
            }
            line.push_str(&format!("\n  script: `{}`", script_path(slug, rule)));
            line
        })
        .collect::<Vec<_>>()
        .join("\n");

    let register = match headless {
        Some(cli) => format!(
            "Registre com `{cli} rules set-test <id> --command \"<caminho do script>\"`"
        ),
        None => "Registre com `set_rule_test` (MCP) ou `vibedeck rules set-test <id> --command \"<caminho do script>\"`".to_string(),
    };
    let manual = match headless {
        Some(cli) => format!(
            "registre como manual: `{cli} rules set-test <id> --manual --reason \"<motivo>\"`"
        ),
        None => {
            "registre como manual: `set_rule_test` com `mode=manual` e `reason` explicando por quê"
                .to_string()
        }
    };
    let violation = if headless.is_none() {
        "verifique se é violação real (avise-me) ou bug do script (corrija)"
    } else {
        "verifique se é violação real (anote no resumo final) ou bug do script (corrija)"
    };
    let ending = if headless.is_none() {
        "No fim, me mostre uma tabela: regra, script ou manual, resultado da primeira execução."
    } else {
        "Você roda em segundo plano, sem ninguém para responder perguntas: não pergunte, decida. No fim, escreva um resumo curto: regra, script ou manual, resultado da primeira execução."
    };
    let scope = if topic.is_global() {
        "O tópico vale para toda tarefa.".to_string()
    } else {
        format!("Escopo do tópico: {}.", topic.paths.join(", "))
    };
    let verb = if selection == PromptSelection::All {
        "Gere"
    } else {
        "Atualize"
    };

    format!(
        "{verb} os testes das regras do tópico \"{title}\" (`{slug}`). O objetivo é que a verificação dessas regras rode um script, sem precisar de você a cada check.\n\
{scope}\n\
\n\
Regras:\n\
{list}\n\
\n\
Para cada regra:\n\
1. Leia o código relevante e decida se a regra é verificável de forma objetiva por um script.\n\
2. Se for, escreva o script no caminho indicado (`#!/usr/bin/env bash`, `set -euo pipefail`, executável com `chmod +x`). Ele roda na raiz do projeto com:\n\
   - `$VIBEDECK_FILES`: arquivos alterados na tarefa, um por linha (pode vir vazio — aí verifique o projeto todo);\n\
   - `$VIBEDECK_ROOT` e `$VIBEDECK_RULE_ID`.\n\
   Saída: `exit 0` = cumpre, `exit 77` = não se aplica a esses arquivos, qualquer outro código = viola. Em caso de falha, imprima o arquivo/linha e o motivo. Seja rápido (limite de 120 s) e determinístico; sem rede.\n\
3. Rode o script e confira o resultado contra o código atual. Se ele falhar, {violation}. Nunca afrouxe a regra só para o script passar.\n\
4. {register}.\n\
5. Se a regra for subjetiva ou depender de julgamento (ex.: \"README atualizado quando muda algo documentado\"), {manual} — ela permanece pendente até a verificação manual solicitada; nunca marque como aprovada sem evidência.\n\
\n\
{ending}",
        title = topic.title,
    )
}

fn severity(rule: &Rule) -> &'static str {
    match rule.severity {
        crate::model::RuleSeverity::Must => "must",
        crate::model::RuleSeverity::Should => "should",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{RuleSeverity, RuleTest, RuleTestMode, Timestamp};

    fn topic() -> RuleTopic {
        let mut t = RuleTopic::new("Geral");
        let mut a = Rule::new("sem teste");
        a.details = Some("linha 1\nlinha 2".into());
        let mut b = Rule::new("com script");
        b.severity = RuleSeverity::Should;
        b.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some("x.sh".into()),
            reason: None,
            rule_hash: b.content_hash(),
            generated_at: Timestamp::now(),
        });
        let mut c = Rule::new("velha");
        c.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some("y.sh".into()),
            reason: None,
            rule_hash: "x".into(),
            generated_at: Timestamp::now(),
        });
        t.rules = vec![a, b, c];
        t
    }

    #[test]
    fn selection_picks_missing_stale_or_all() {
        let t = topic();
        assert_eq!(rules_for_selection(&t, PromptSelection::Missing).len(), 1);
        assert_eq!(rules_for_selection(&t, PromptSelection::Stale).len(), 1);
        assert_eq!(rules_for_selection(&t, PromptSelection::Pending).len(), 2);
        assert_eq!(rules_for_selection(&t, PromptSelection::All).len(), 3);
    }

    #[test]
    fn prompt_lists_only_pending_rules() {
        let t = topic();
        let p = generate_prompt("geral", &t, PromptSelection::Pending, None);
        assert!(p.starts_with("Atualize os testes das regras do tópico \"Geral\" (`geral`)."));
        assert!(p.contains("sem teste"));
        assert!(p.contains("  > linha 1\n  > linha 2"));
        assert!(!p.contains("com script"));
        assert!(p.contains("(a regra mudou desde o teste atual: `y.sh` — reescreva)"));
        assert!(p.contains("O tópico vale para toda tarefa."));
        assert!(p.contains("Registre com `set_rule_test` (MCP)"));
        assert!(p.contains("script: `.vibedeck/tests/geral/"));
        assert!(
            generate_prompt("geral", &t, PromptSelection::All, None).starts_with("Gere os testes")
        );
    }

    #[test]
    fn headless_prompt_registers_through_cli() {
        let t = topic();
        let p = generate_prompt("geral", &t, PromptSelection::Missing, Some("/bin/vibedeck"));
        assert!(p.contains("`/bin/vibedeck rules set-test <id> --command"));
        assert!(p.contains("`/bin/vibedeck rules set-test <id> --manual --reason"));
        assert!(p.contains("sem ninguém para responder perguntas"));
        assert!(!p.contains("set_rule_test"));
    }
}
