//! Prompts: o da etapa (para o subagente) e o do orquestrador (para o chat).

use std::collections::HashSet;
use std::path::Path;

use super::ext::kind_str;
use crate::model::*;

/// `AIPromptPolicy.instructions` (política compartilhada de instruções de IA).
const POLICY: &str = include_str!("policy.txt");
const ORCHESTRATOR: &str = include_str!("orchestrator.txt");

fn non_empty(s: &Option<String>) -> Option<&str> {
    s.as_deref().map(str::trim).filter(|s| !s.is_empty())
}

/// Vereditos que as transições da etapa esperam, sem repetição (por forma normalizada).
pub fn expected_verdicts(step: &WorkflowStep) -> Vec<String> {
    let mut seen = HashSet::new();
    step.transitions
        .iter()
        .filter_map(|t| t.verdict.clone())
        .filter(|v| seen.insert(WorkflowTransition::normalize(v)))
        .collect()
}

/// Tudo de que o subagente da etapa precisa: instruções resolvidas, pasta e histórico da execução, respostas
/// do usuário a esta execução e o protocolo de saída. O orquestrador passa só a referência da execução.
#[allow(clippy::too_many_arguments)]
pub fn step_prompt(
    run: &WorkflowRun,
    reference: &str,
    workflow: &Workflow,
    step: &WorkflowStep,
    title: Option<&str>,
    instructions: Option<&str>,
    run_dir: &Path,
    cli: &str,
) -> String {
    let input = run.input.clone().unwrap_or_default();
    let run_dir_str = run_dir.to_string_lossy().into_owned();
    let arguments = non_empty(&step.note)
        .map(str::to_string)
        .unwrap_or_else(|| input.clone());
    let mut body = instructions.unwrap_or("").replace("$RUN_DIR", &run_dir_str);
    if step.kind == NextStepKind::Command {
        body = body.replace("$ARGUMENTS", &arguments);
    }
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!(
        "# Etapa `{}` — {}",
        step.id,
        title.unwrap_or(&step.r#ref)
    ));
    lines.push(String::new());
    lines.push(format!(
        "Você executa **uma** etapa do workflow \"{}\" do VibeDeck (execução `{reference}`), a pedido do orquestrador. Tudo o que você precisa está aqui e no disco.",
        workflow.title
    ));
    lines.push(String::new());
    lines.push(format!(
        "- Entrada da execução: {}",
        if input.is_empty() {
            "(nenhuma)"
        } else {
            &input
        }
    ));
    lines.push(format!(
        "- Pasta da execução (`$RUN_DIR`): `{run_dir_str}` — leia o que as etapas anteriores gravaram e grave aqui o que esta etapa produz."
    ));
    if step.kind != NextStepKind::Command
        && let Some(note) = non_empty(&step.note)
    {
        lines.push(format!("- Instrução extra desta etapa: {note}"));
    }
    lines.push(format!(
        "- Histórico completo e decisões anteriores: `{}`. Consulte quando uma referência ou decisão anterior for necessária.",
        run_dir.join("run.json").to_string_lossy()
    ));
    let history = &run.history;
    if history.len() > 3 {
        lines.push(
            "Histórico anterior (consulte run.json para evidências e pendências):".to_string(),
        );
        for entry in &history[..history.len() - 3] {
            lines.push(format!(
                "- `{}` → {}",
                entry.step,
                entry.verdict.as_deref().unwrap_or("sem veredito")
            ));
        }
    }
    let previous = &history[history.len().saturating_sub(3)..];
    if !previous.is_empty() {
        lines.push(String::new());
        lines.push("## Etapas anteriores".to_string());
        for (n, e) in previous.iter().enumerate() {
            lines.push(format!(
                "{}. `{}` → {}{}",
                n + 1,
                e.step,
                e.verdict.as_deref().unwrap_or("—"),
                e.summary
                    .as_ref()
                    .map(|s| format!(": {s}"))
                    .unwrap_or_default()
            ));
        }
    }
    let answers: Vec<&WorkflowQuestion> = run
        .questions
        .iter()
        .filter(|q| q.answer.is_some())
        .collect();
    if !answers.is_empty() {
        lines.push(String::new());
        lines.push("## Decisões do usuário nesta execução".to_string());
        lines.push("São decisões do usuário: use cada uma quando chegar àquele ponto, sem perguntar de novo.".to_string());
        for q in answers {
            lines.push(format!(
                "- **{}** → {}",
                q.question,
                q.answer.as_deref().unwrap_or("")
            ));
        }
    }
    lines.push(String::new());
    lines.push(POLICY.to_string());
    lines.push("## Instruções da etapa".to_string());
    lines.push(String::new());
    let trimmed_body = body.trim();
    lines.push(if trimmed_body.is_empty() {
        format!(
            "(a etapa não tem instruções: {} `{}` não encontrado)",
            kind_str(step.kind),
            step.r#ref
        )
    } else {
        trimmed_body.to_string()
    });
    lines.push(String::new());
    lines.push("## Protocolo".to_string());
    lines.push(
        "1. Siga as instruções até o fim. Portões, arquivos gravados e formato da saída são delas."
            .to_string(),
    );
    lines.push("2. Você **não** fala com o usuário. Onde as instruções mandarem perguntar ou pedirem uma decisão do usuário, e não houver resposta acima: não adivinhe e não faça nada irreversível antes. Grave as perguntas (de 2 a 4 opções cada, a recomendada primeiro):".to_string());
    lines.push("   ```bash".to_string());
    lines.push(format!("   {cli} runs ask {reference} <<'__FIM__'"));
    lines.push("   [{\"question\": \"<pergunta direta>\", \"context\": \"<o que gerou a dúvida>\", \"options\": [{\"label\": \"<1 a 5 palavras>\", \"description\": \"<o que acontece>\"}], \"multiple\": false}]".to_string());
    lines.push("   __FIM__".to_string());
    lines.push("   ```".to_string());
    lines.push(
        "   e termine com um resumo curto de onde parou e a **última linha, sozinha:** `PERGUNTA`."
            .to_string(),
    );
    let verdicts = expected_verdicts(step);
    if verdicts.is_empty() {
        lines.push("3. Ao terminar, devolva a saída final com a **última linha, sozinha,** sendo o veredito da etapa (uma palavra ou frase curta).".to_string());
    } else {
        let list = verdicts
            .iter()
            .map(|v| format!("`{v}`"))
            .collect::<Vec<_>>()
            .join(", ");
        lines.push(format!(
            "3. Ao terminar, devolva a saída final com a **última linha, sozinha,** sendo o veredito: {list} (ou outro, se as instruções definirem)."
        ));
    }
    lines.push(format!(
        "4. Não chame `{cli} runs record`: quem registra o veredito é o orquestrador."
    ));
    lines.join("\n")
}

/// Substituição de `{nome}` em uma só passada (o valor inserido nunca é reinterpretado).
fn render(template: &str, vars: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(template.len() + 256);
    let mut rest = template;
    'outer: while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let tail = &rest[open..];
        for (name, value) in vars {
            let key = format!("{{{name}}}");
            if tail.starts_with(&key) {
                out.push_str(value);
                rest = &tail[key.len()..];
                continue 'outer;
            }
        }
        out.push('{');
        rest = &tail[1..];
    }
    out.push_str(rest);
    out
}

/// Mensagem que faz do chat o orquestrador de uma execução (como `/conduzir` + o `operador` do claude-kit).
pub fn orchestrator_prompt(
    reference: &str,
    title: &str,
    input: Option<&str>,
    cli: &str,
    provider: AiProvider,
) -> String {
    let input_part = input
        .map(|i| format!(" (entrada: {i})"))
        .unwrap_or_default();
    let prompt = render(
        ORCHESTRATOR,
        &[
            ("ref", reference),
            ("title", title),
            ("cli", cli),
            ("input_part", &input_part),
        ],
    );
    if provider != AiProvider::Codex {
        return prompt;
    }
    prompt
        .replace(
            "(`Agent`, ",
            "(a ferramenta de subagente disponível no Codex, ",
        )
        .replace(
            "`subagent_type: \"general-purpose\"`, `model` = o `model` da ação quando houver, `description: \"<step>\"`)",
            "contexto limpo; use o modelo configurado para Codex quando disponível)",
        )
        .replace(
            "faça-as com `AskUserQuestion` (até 4 por vez, na ",
            "apresente-as ao usuário (até 4 por vez, na ",
        )
}
