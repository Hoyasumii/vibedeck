//! O que `rules_for` e `submit_rule_check` entregam ao agente (`RuleAgentOutput.swift`). Os dois são
//! pagos a cada tarefa, então o padrão é compacto; a forma completa fica em `verbose`.

use serde::Serialize;
use serde_json::Value;

use crate::json;
use crate::model::{RuleCheck, RuleResultSource, RuleSeverity, RuleTopic};
use crate::store::Record;

use super::error::{Result, RuleError};
use super::rule::{RuleExt, RuleTestState};

/// Resumo para o agente: veredito, todas as falhas e avisos, a saída do script reprovado e onde o check
/// completo está. Notas de aprovação ficam de fora (estão no arquivo). `verbose` anexa o JSON completo.
pub fn agent_summary(check: &RuleCheck, verbose: bool) -> Result<String> {
    let mut summary = if check.passed {
        format!("✅ Check aprovado ({} regra(s)).", check.results.len())
    } else {
        format!(
            "❌ Check reprovado. Corrija e envie um novo check antes de concluir:\n{}",
            check
                .failures
                .iter()
                .map(|f| format!("- {f}"))
                .collect::<Vec<_>>()
                .join("\n")
        )
    };
    if !check.warnings.is_empty() {
        summary.push_str("\n⚠️ Recomendações não cumpridas (avise o usuário):\n");
        summary.push_str(
            &check
                .warnings
                .iter()
                .map(|w| format!("- {w}"))
                .collect::<Vec<_>>()
                .join("\n"),
        );
    }
    if !check.pending.is_empty() {
        summary.push_str(&format!(
            "\n⏭️ {} regra(s) manual(is) não verificada(s) (peça verify_manual=true para checá-las): ",
            check.pending.len()
        ));
        summary.push_str(
            &check
                .pending
                .iter()
                .take(5)
                .cloned()
                .collect::<Vec<_>>()
                .join("; "),
        );
        if check.pending.len() > 5 {
            summary.push_str("; …");
        }
    }
    let scripted: Vec<_> = check
        .results
        .iter()
        .filter(|r| r.source == RuleResultSource::Script)
        .collect();
    if !scripted.is_empty() {
        summary.push_str(&format!(
            "\n⚙️ {} regra(s) decidida(s) por script.",
            scripted.len()
        ));
        for r in scripted
            .iter()
            .filter(|r| r.verdict == crate::model::RuleVerdict::Fail)
        {
            summary.push_str(&format!(
                "\n--- script reprovado:\n{}",
                r.note.as_deref().unwrap_or("")
            ));
        }
    }
    let id8: String = check
        .id
        .to_string()
        .to_lowercase()
        .chars()
        .take(8)
        .collect();
    summary.push_str(&format!(
        "\nCheck {id8}: .vibedeck/checks/{}",
        check.file_name()
    ));
    if !verbose {
        return Ok(summary);
    }
    let bytes = json::encode(check).map_err(crate::error::Error::Encode)?;
    let mut full = String::from_utf8_lossy(&bytes).into_owned();
    if full.ends_with('\n') {
        full.pop();
    }
    Ok(format!("{summary}\n{full}"))
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleRow {
    pub rule_id: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    pub severity: RuleSeverity,
    /// `script`: decidida rodando `test` em submit_rule_check; `manual`: o agente responde.
    pub check: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub test: Option<String>,
    /// A regra mudou depois do teste: responda manualmente e regenere o teste.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stale_test: Option<bool>,
}

/// Regras de um tópico como checklist do agente (`rules_for`, `get_rule_topic`, `vibedeck rules ... --json`).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TopicChecklist {
    pub slug: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub paths: Option<Vec<String>>,
    pub rules: Vec<RuleRow>,
    /// Regras manuais que ficaram fora de `rules` (ver `include_manual`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manual_rules: Option<usize>,
}

impl TopicChecklist {
    /// Forma completa: ids inteiros, descrição, paths e o comando do script.
    pub fn new(slug: &str, topic: &RuleTopic, include_manual: bool) -> Self {
        Self::build(slug, topic, include_manual, false, 36)
    }

    /// `compact` tira o que o agente não precisa para agir: descrição e paths do tópico e o caminho dos
    /// scripts (submit_rule_check os roda sozinho). `id_length` encurta os ids das regras.
    fn build(
        slug: &str,
        topic: &RuleTopic,
        include_manual: bool,
        compact: bool,
        id_length: usize,
    ) -> Self {
        let listed: Vec<_> = topic
            .rules
            .iter()
            .filter(|r| include_manual || r.test_state() == RuleTestState::Script)
            .collect();
        let manual_rules =
            (listed.len() < topic.rules.len()).then(|| topic.rules.len() - listed.len());
        TopicChecklist {
            slug: slug.to_string(),
            title: topic.title.clone(),
            description: if compact {
                None
            } else {
                topic.description.clone()
            },
            paths: if compact {
                None
            } else {
                Some(topic.paths.clone())
            },
            rules: listed
                .into_iter()
                .map(|r| RuleRow {
                    rule_id: r.id.to_string().chars().take(id_length).collect(),
                    text: r.text.clone(),
                    details: if include_manual {
                        r.details.clone()
                    } else {
                        None
                    },
                    severity: r.severity,
                    check: if r.test_state() == RuleTestState::Script {
                        "script"
                    } else {
                        "manual"
                    },
                    test: if compact { None } else { r.script_command() },
                    stale_test: (r.test_state() == RuleTestState::Stale).then_some(true),
                })
                .collect(),
            manual_rules,
        }
    }

    /// Resposta padrão de `rules_for`. Os ids das regras têm 8 caracteres (submit_rule_check resolve
    /// prefixos), ou inteiros se duas regras da resposta dividissem um.
    pub fn compact(topics: &[Record<RuleTopic>], include_manual: bool) -> Vec<TopicChecklist> {
        let prefixes: Vec<String> = topics
            .iter()
            .flat_map(|t| t.value.rules.iter())
            .map(|r| r.id.to_string().chars().take(8).collect())
            .collect();
        let distinct: std::collections::HashSet<&String> = prefixes.iter().collect();
        let id_length = if distinct.len() == prefixes.len() {
            8
        } else {
            36
        };
        topics
            .iter()
            .map(|t| Self::build(&t.slug, &t.value, include_manual, true, id_length))
            .collect()
    }

    /// JSON de uma linha: a indentação é custo puro de tokens para o agente.
    pub fn compact_json(checklists: &[TopicChecklist]) -> Result<String> {
        let value: Value = serde_json::to_value(checklists)
            .map_err(|e| RuleError::Core(crate::error::Error::Encode(e)))?;
        Ok(json::to_compact(&value))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Rule, RuleTest, RuleTestMode, Timestamp};

    fn topic() -> RuleTopic {
        let mut t = RuleTopic::new("Geral");
        t.description = Some("desc".into());
        t.paths = vec!["src/**".into()];
        let mut scripted = Rule::new("com script");
        scripted.details = Some("como".into());
        scripted.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some("x.sh".into()),
            reason: None,
            rule_hash: scripted.content_hash(),
            generated_at: Timestamp::now(),
        });
        let mut stale = Rule::new("velha");
        stale.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some("y.sh".into()),
            reason: None,
            rule_hash: "0000".into(),
            generated_at: Timestamp::now(),
        });
        t.rules = vec![scripted, stale, Rule::new("manual")];
        t
    }

    #[test]
    fn full_and_manual_counts() {
        let t = topic();
        let full = TopicChecklist::new("geral", &t, true);
        assert_eq!(full.rules.len(), 3);
        assert_eq!(full.rules[0].check, "script");
        assert_eq!(full.rules[0].test.as_deref(), Some("x.sh"));
        assert_eq!(full.rules[1].stale_test, Some(true));
        assert_eq!(full.rules[1].check, "manual");
        assert_eq!(full.rules[0].rule_id.len(), 36);
        assert_eq!(full.paths.as_deref(), Some(&["src/**".to_string()][..]));
        let scripts_only = TopicChecklist::new("geral", &t, false);
        assert_eq!(scripts_only.rules.len(), 1);
        assert_eq!(scripts_only.manual_rules, Some(2));
        assert!(scripts_only.rules[0].details.is_none());
        assert!(full.manual_rules.is_none());
    }

    #[test]
    fn compact_json_is_short_and_sorted() {
        let t = topic();
        let recs = vec![Record {
            slug: "geral".to_string(),
            value: t,
        }];
        let c = TopicChecklist::compact(&recs, false);
        let json = TopicChecklist::compact_json(&c).unwrap();
        assert!(!json.contains('\n') && !json.contains(": "));
        assert!(json.starts_with(r#"[{"manualRules":2,"rules":[{"check":"script","ruleId":""#));
        assert!(json.contains(r#""severity":"must""#));
        assert!(!json.contains("x.sh") && !json.contains("desc") && !json.contains("paths"));
        let id8 = &recs[0].value.rules[0].id.to_string()[..8].to_string();
        assert!(json.contains(&format!(r#""ruleId":"{id8}""#)));
    }

    #[test]
    fn compact_uses_full_ids_when_prefixes_collide() {
        let mut t = RuleTopic::new("G");
        let mut a = Rule::new("a");
        let mut b = Rule::new("b");
        a.id = "AAAA0000-0000-4000-8000-000000000001".parse().unwrap();
        b.id = "AAAA0000-0000-4000-8000-000000000002".parse().unwrap();
        t.rules = vec![a, b];
        let recs = vec![Record {
            slug: "g".to_string(),
            value: t,
        }];
        let c = TopicChecklist::compact(&recs, true);
        assert_eq!(c[0].rules[0].rule_id.len(), 36);
    }
}
