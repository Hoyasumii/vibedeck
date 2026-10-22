//! "Resolver" em itens de revisão — só a parte que não depende de provider de IA: quais itens participam,
//! os prompts, o plano validado e o laço item a item. A chamada ao provider (planejar/executar) e o
//! `verify` (que roda `submit_check`) ficam na área `ai`/`rules`.
//!
//! Nada aqui remove item nem grava `wontfix`.

use serde::Deserialize;

use super::discover::{DiscoverError, TOOLS};
use crate::model::*;

/// Fase somente leitura: as mesmas ferramentas do `ReviewDiscover`.
pub const PLAN_TOOLS: [&str; 3] = TOOLS;
/// Perguntas que a IA pode fazer antes de entregar o plano (uma rodada).
pub const MAX_QUESTIONS: usize = 5;

/// Só `open` e `in_progress` vão para a IA; `done` e `wontfix` nunca são enviados nem tocados.
pub fn eligible(items: &[ReviewItem]) -> Vec<ReviewItem> {
    items
        .iter()
        .filter(|i| matches!(i.status, ReviewStatus::Open | ReviewStatus::InProgress))
        .cloned()
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub summary: String,
    pub steps: Vec<String>,
    /// Caminhos relativos à raiz que a IA espera alterar; delimitam o check.
    pub files: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Question {
    pub id: usize,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reply {
    Questions(Vec<Question>),
    Plan(Plan),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Answered {
    pub question: String,
    pub answer: String,
}

pub const SCHEMA: &str = r#"{"type":"object","properties":{"questions":{"type":"array","items":{"type":"string"}},"summary":{"type":"string"},"steps":{"type":"array","items":{"type":"string"}},"files":{"type":"array","items":{"type":"string"}}},"required":["questions","summary","steps","files"]}"#;

#[derive(Deserialize)]
struct Raw {
    questions: Option<Vec<String>>,
    summary: Option<String>,
    steps: Option<Vec<String>>,
    files: Option<Vec<String>>,
}

fn trimmed(list: Option<Vec<String>>) -> Vec<String> {
    list.unwrap_or_default()
        .into_iter()
        .map(|s| s.trim().to_string())
        .collect()
}

/// Valida a resposta da IA. Com perguntas é um `Questions` (só se `allow_questions`); senão exige resumo
/// e ao menos um passo. JSON malformado, campos vazios e caminhos fora do projeto dão `InvalidAnswer`.
pub fn parse(data: &[u8], allow_questions: bool) -> Result<Reply, DiscoverError> {
    let raw: Raw = serde_json::from_slice(data).map_err(|_| DiscoverError::InvalidAnswer)?;
    let questions = trimmed(raw.questions);
    if !questions.is_empty() {
        if !allow_questions
            || questions.iter().any(String::is_empty)
            || questions.len() > MAX_QUESTIONS
        {
            return Err(DiscoverError::InvalidAnswer);
        }
        return Ok(Reply::Questions(
            questions
                .into_iter()
                .enumerate()
                .map(|(id, text)| Question { id, text })
                .collect(),
        ));
    }
    let summary = raw.summary.unwrap_or_default().trim().to_string();
    let steps = trimmed(raw.steps);
    let files = trimmed(raw.files);
    if summary.is_empty()
        || steps.is_empty()
        || steps.iter().any(String::is_empty)
        || files.iter().any(|f| !is_project_relative(f))
    {
        return Err(DiscoverError::InvalidAnswer);
    }
    Ok(Reply::Plan(Plan {
        summary,
        steps,
        files,
    }))
}

pub fn is_project_relative(path: &str) -> bool {
    !path.is_empty()
        && !path.starts_with('/')
        && !path.starts_with('~')
        && !path.split('/').any(|p| p == "..")
}

fn item_lines(item: &ReviewItem, kind: &str) -> Vec<String> {
    let mut lines = vec![
        format!("Título: {}", item.title),
        format!("Tipo: {kind}"),
        format!("Prioridade: {}", priority_label(item.priority)),
    ];
    if let Some(d) = item.details.as_deref().filter(|d| !d.is_empty()) {
        lines.push(format!("Detalhes: {d}"));
    }
    if let Some(t) = &item.target {
        let target: Vec<String> = [
            ("arquivo", &t.file),
            ("rota", &t.route),
            ("componente", &t.component),
            ("seletor", &t.selector),
        ]
        .iter()
        .filter_map(|(n, v)| v.as_ref().map(|v| format!("{n} = {v}")))
        .collect();
        if !target.is_empty() {
            lines.push(format!("Onde: {}", target.join("; ")));
        }
    }
    lines
}

/// `ReviewPriority.label`.
pub fn priority_label(p: ReviewPriority) -> &'static str {
    match p {
        ReviewPriority::Low => "Baixa",
        ReviewPriority::Normal => "Normal",
        ReviewPriority::High => "Alta",
    }
}

/// Prompt de planejamento. Sem `answers` a IA pode perguntar; com elas precisa entregar o plano.
pub fn plan_prompt(item: &ReviewItem, kind: &str, answers: &[Answered]) -> String {
    let mut lines: Vec<String> = vec![
        "Você vai planejar a resolução de um item de revisão do VibeDeck neste repositório (o diretório atual).".into(),
        "Use só leitura e busca. Não altere nada nesta etapa.".into(),
        String::new(),
        "## Item".into(),
    ];
    lines.extend(item_lines(item, kind));
    if !answers.is_empty() {
        lines.push(String::new());
        lines.push("## Respostas do usuário".into());
        for pair in answers {
            lines.push(format!("- {} → {}", pair.question, pair.answer));
        }
    }
    lines.push(String::new());
    lines.push("## Resposta".into());
    if answers.is_empty() {
        lines.push(format!("- questions: perguntas que você realmente precisa que o usuário responda (no máximo {MAX_QUESTIONS}); vazio se não houver dúvida. Com perguntas, deixe summary vazio e steps/files vazios."));
    } else {
        lines.push("- questions: deve ficar vazio; entregue o plano.".into());
    }
    lines.extend([
        "- summary: o que será feito, em uma ou duas frases.".to_string(),
        "- steps: passos concretos e curtos, na ordem.".to_string(),
        "- files: caminhos relativos à raiz dos arquivos que você espera alterar (sem .., sem caminho absoluto).".to_string(),
        "Escreva tudo em português do Brasil.".to_string(),
    ]);
    lines.join("\n")
}

/// Prompt de execução, enviado só depois que o usuário aceitou o `plan`.
pub fn execution_prompt(
    item: &ReviewItem,
    kind: &str,
    plan: &Plan,
    answers: &[Answered],
) -> String {
    let mut lines: Vec<String> = vec![
        "Resolva o item de revisão abaixo neste repositório (o diretório atual), seguindo o plano aceito pelo usuário.".into(),
        String::new(),
        "## Item".into(),
    ];
    lines.extend(item_lines(item, kind));
    if !answers.is_empty() {
        lines.push(String::new());
        lines.push("## Respostas do usuário".into());
        for pair in answers {
            lines.push(format!("- {} → {}", pair.question, pair.answer));
        }
    }
    lines.push(String::new());
    lines.push("## Plano aceito".into());
    lines.push(plan.summary.clone());
    for (index, step) in plan.steps.iter().enumerate() {
        lines.push(format!("{}. {step}", index + 1));
    }
    if !plan.files.is_empty() {
        lines.push(format!("Arquivos previstos: {}", plan.files.join(", ")));
    }
    let id = item.id.to_string();
    lines.extend([
        String::new(),
        "## Verificação".to_string(),
        format!("- Use rules_for e submit_rule_check no MCP vibedeck com review_item={id} e os arquivos realmente alterados; sem MCP, use os equivalentes vibedeck rules for/check --item {id}."),
        "- No Codex, rode os scripts pelo MCP do VibeDeck, fora do terminal do agente, sem alterar o sandbox nem dispensar checks.".to_string(),
        "- Para concluir o item, confira também as regras manuais must: include_manual=true, depois verify_manual=true com evidência para cada manual. Não aprove sem verificar.".to_string(),
        String::new(),
        "## Limites".to_string(),
        "- Altere apenas arquivos dentro do diretório atual e só o que o plano pede.".to_string(),
        "- Não edite .vibedeck/reviews nem o status do item: o app muda o status depois do check.".to_string(),
        "- Não apague o item nem o marque como não fazer.".to_string(),
        "- Se não conseguir resolver, explique o motivo e pare; não force.".to_string(),
        "Escreva em português do Brasil.".to_string(),
    ]);
    lines.join("\n")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Resolved,
    Failed(String),
    Cancelled,
    /// Nunca tentado: a execução foi cancelada antes de chegar nele.
    Skipped,
}

/// Itens um a um. Falha (erro ou `Failed`) não para os próximos nem desfaz os concluídos; `Cancelled` para
/// o laço e deixa os restantes `Skipped`. `attempt` devolve `Err(msg)` para uma falha lançada.
/// (`is_cancelled` substitui `Task.isCancelled`: consultado antes de cada item.)
pub fn resolve_sequentially<F, C>(
    items: &[ReviewItem],
    mut attempt: F,
    is_cancelled: C,
) -> Vec<(Id, Outcome)>
where
    F: FnMut(&ReviewItem) -> Result<Outcome, String>,
    C: Fn() -> bool,
{
    let mut results = Vec::new();
    let mut stopped = false;
    for item in items {
        if stopped || is_cancelled() {
            results.push((item.id, Outcome::Skipped));
            stopped = true;
            continue;
        }
        match attempt(item) {
            Ok(outcome) => {
                let cancelled = outcome == Outcome::Cancelled;
                results.push((item.id, outcome));
                if cancelled {
                    stopped = true;
                }
            }
            Err(msg) => results.push((item.id, Outcome::Failed(msg))),
        }
    }
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(title: &str, status: ReviewStatus) -> ReviewItem {
        let mut i = ReviewItem::new("fix", title);
        i.status = status;
        i
    }

    #[test]
    fn so_open_e_in_progress() {
        let items: Vec<ReviewItem> = [
            ReviewStatus::Open,
            ReviewStatus::InProgress,
            ReviewStatus::Done,
            ReviewStatus::Wontfix,
        ]
        .iter()
        .map(|s| item(&format!("{s:?}"), *s))
        .collect();
        let eligible = eligible(&items);
        assert_eq!(eligible.len(), 2);
        let prompts: String = eligible
            .iter()
            .map(|i| plan_prompt(i, "Corrigir", &[]))
            .collect();
        assert!(prompts.contains("Título: Open") && prompts.contains("Título: InProgress"));
        assert!(!prompts.contains("Título: Done") && !prompts.contains("Título: Wontfix"));
        assert_eq!(PLAN_TOOLS, ["Read", "Grep", "Glob"]);
    }

    #[test]
    fn plano_e_perguntas_validos() {
        let plan = parse(
            br#"{"questions":[],"summary":" Ajustar ","steps":["a","b"],"files":["Sources/A.swift"]}"#,
            true,
        )
        .unwrap();
        assert_eq!(
            plan,
            Reply::Plan(Plan {
                summary: "Ajustar".into(),
                steps: vec!["a".into(), "b".into()],
                files: vec!["Sources/A.swift".into()]
            })
        );
        let q = parse(
            br#"{"questions":["Qual tela?"],"summary":"","steps":[],"files":[]}"#,
            true,
        )
        .unwrap();
        assert_eq!(
            q,
            Reply::Questions(vec![Question {
                id: 0,
                text: "Qual tela?".into()
            }])
        );
    }

    #[test]
    fn respostas_invalidas() {
        let invalid: [(&str, bool); 9] = [
            ("não é json", true),
            (r#"{"questions":"x"}"#, true),
            (
                r#"{"questions":[],"summary":"","steps":["a"],"files":[]}"#,
                true,
            ),
            (
                r#"{"questions":[],"summary":"x","steps":[],"files":[]}"#,
                true,
            ),
            (
                r#"{"questions":[],"summary":"x","steps":["  "],"files":[]}"#,
                true,
            ),
            (
                r#"{"questions":[" "],"summary":"","steps":[],"files":[]}"#,
                true,
            ),
            (
                r#"{"questions":["?"],"summary":"","steps":[],"files":[]}"#,
                false,
            ),
            (
                r#"{"questions":[],"summary":"x","steps":["a"],"files":["../fora"]}"#,
                true,
            ),
            (
                r#"{"questions":[],"summary":"x","steps":["a"],"files":["/etc/passwd"]}"#,
                true,
            ),
        ];
        for (json, allow) in invalid {
            assert_eq!(
                parse(json.as_bytes(), allow),
                Err(DiscoverError::InvalidAnswer),
                "{json}"
            );
        }
    }

    #[test]
    fn prompt_de_execucao() {
        let it = ReviewItem::new("fix", "Botão");
        let plan = Plan {
            summary: "Fazer X".into(),
            steps: vec!["um".into()],
            files: vec!["A.swift".into()],
        };
        let answers = [Answered {
            question: "Qual?".into(),
            answer: "Esta".into(),
        }];
        let p = execution_prompt(&it, "Corrigir", &plan, &answers);
        assert!(p.contains("Fazer X") && p.contains("1. um") && p.contains("Qual? → Esta"));
        assert!(p.contains("Não apague o item"));
        assert!(p.contains(&format!("review_item={}", it.id)));
        assert!(p.contains("rules_for e submit_rule_check no MCP vibedeck"));
        assert!(p.contains("verify_manual=true com evidência"));
    }

    #[test]
    fn laco_sequencial() {
        let items: Vec<ReviewItem> = (1..=3)
            .map(|n| ReviewItem::new("fix", format!("i{n}")))
            .collect();
        let mut attempted = vec![];
        let r = resolve_sequentially(
            &items,
            |i| {
                attempted.push(i.title.clone());
                Ok(if i.title == "i2" {
                    Outcome::Failed("check".into())
                } else {
                    Outcome::Resolved
                })
            },
            || false,
        );
        assert_eq!(attempted, ["i1", "i2", "i3"]);
        let o: Vec<_> = r.into_iter().map(|(_, o)| o).collect();
        assert_eq!(
            o,
            [
                Outcome::Resolved,
                Outcome::Failed("check".into()),
                Outcome::Resolved
            ]
        );

        let thrown = resolve_sequentially(
            &items,
            |i| {
                if i.title == "i1" {
                    Err("boom".into())
                } else {
                    Ok(Outcome::Resolved)
                }
            },
            || false,
        );
        assert_eq!(thrown[0].1, Outcome::Failed("boom".into()));
        assert_eq!(thrown[2].1, Outcome::Resolved);

        let cancelled = resolve_sequentially(
            &items,
            |i| {
                Ok(if i.title == "i2" {
                    Outcome::Cancelled
                } else {
                    Outcome::Resolved
                })
            },
            || false,
        );
        let o: Vec<_> = cancelled.into_iter().map(|(_, o)| o).collect();
        assert_eq!(o, [Outcome::Resolved, Outcome::Cancelled, Outcome::Skipped]);
    }
}
