//! Escopo de uma tarefa, execução dos scripts, `submitCheck` e portões de verificação
//! (trechos de `ProjectStore.swift`, "// MARK: Checks").

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::model::{
    Author, Id, ReviewItem, Rule, RuleCheck, RuleResult, RuleResultSource, RuleSeverity, RuleTopic,
    RuleVerdict, TimestampMs, project::schema_url,
};
use crate::store::{Record, Store};

use super::error::{Result, RuleError};
use super::execution::{RuleScriptEvent, RuleTestRun, RuleTestRunner, RunOptions, run_scripts};
use super::rule::{RuleExt, trimmed_non_empty};
use super::topics::{
    applicable_topics, find_review_item, list_topics, load_topic, match_rule, relative_path,
    resolve_topic_slug,
};

/// Arquivos, tópicos extras e item de revisão de uma tarefa.
#[derive(Debug, Clone, Default)]
pub struct TaskSpec {
    pub files: Vec<String>,
    pub topics: Vec<String>,
    pub review_item: Option<String>,
}

/// Arquivos (relativos, únicos e ordenados), tópicos aplicáveis e o item de revisão de uma tarefa.
pub struct TaskScope {
    pub files: Vec<String>,
    pub topics: Vec<Record<RuleTopic>>,
    pub item: Option<Id>,
}

/// Os arquivos e tópicos dados somados aos do item de revisão (`rules` e `target.file`).
pub fn task_scope(store: &Store, spec: &TaskSpec) -> Result<TaskScope> {
    let mut files: Vec<String> = spec.files.iter().map(|f| relative_path(store, f)).collect();
    let mut explicit = spec.topics.clone();
    let mut item_id = None;
    if let Some(reference) = &spec.review_item {
        let item = find_review_item(store, reference)?;
        item_id = Some(item.id);
        explicit.extend(item.rules.iter().cloned());
        if let Some(file) = item.target.as_ref().and_then(|t| t.file.as_deref()) {
            files.push(relative_path(store, file));
        }
    }
    let topics = applicable_topics(store, &files, &explicit)?;
    files.sort();
    files.dedup();
    Ok(TaskScope {
        files,
        topics,
        item: item_id,
    })
}

fn candidates(topics: &[Record<RuleTopic>]) -> Vec<(String, Rule)> {
    topics
        .iter()
        .flat_map(|t| t.value.rules.iter().map(|r| (t.slug.clone(), r.clone())))
        .collect()
}

/// Roda os scripts das regras aplicáveis decididas por script (testes desatualizados não rodam).
/// `only_topics`: só os tópicos citados em `spec.topics` (sem arquivos, roda exatamente esses).
pub fn run_rule_tests(
    store: &Store,
    spec: &TaskSpec,
    only_topics: bool,
    runner: &RuleTestRunner,
) -> Result<Vec<RuleTestRun>> {
    run_rule_tests_with(
        store,
        spec,
        only_topics,
        runner,
        &RunOptions::default(),
        &|_| {},
    )
}

pub fn run_rule_tests_with(
    store: &Store,
    spec: &TaskSpec,
    only_topics: bool,
    runner: &RuleTestRunner,
    opts: &RunOptions,
    on_event: &(dyn Fn(RuleScriptEvent) + Sync),
) -> Result<Vec<RuleTestRun>> {
    let scope = task_scope(store, spec)?;
    let mut named = std::collections::HashSet::new();
    for reference in &spec.topics {
        named.insert(resolve_topic_slug(store, reference)?);
    }
    let topics: Vec<Record<RuleTopic>> = if only_topics {
        scope
            .topics
            .into_iter()
            .filter(|t| named.contains(&t.slug))
            .collect()
    } else {
        scope.topics
    };
    Ok(run_scripts(
        store.root(),
        &candidates(&topics),
        &scope.files,
        runner,
        opts,
        on_event,
    ))
}

/// Linha de `run_rule_tests` / `vibedeck rules test --json`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleTestRunRow {
    pub topic: String,
    pub rule_id: String,
    pub text: String,
    pub severity: RuleSeverity,
    pub command: String,
    pub verdict: RuleVerdict,
    pub exit_code: i32,
    pub output: String,
}

impl From<&RuleTestRun> for RuleTestRunRow {
    fn from(run: &RuleTestRun) -> Self {
        RuleTestRunRow {
            topic: run.topic.clone(),
            rule_id: run.rule.id.to_string(),
            text: run.rule.text.clone(),
            severity: run.rule.severity,
            command: run.command.clone(),
            verdict: run.outcome.verdict,
            exit_code: run.outcome.exit_code,
            output: run.outcome.output.clone(),
        }
    }
}

/// Resposta do agente a uma regra: `ruleId` pode ser o id completo ou um prefixo único (>= 4).
#[derive(Debug, Clone, Deserialize)]
pub struct RuleAnswer {
    #[serde(rename = "ruleId", alias = "rule_id")]
    pub rule_id: String,
    pub verdict: RuleVerdict,
    #[serde(default)]
    pub note: Option<String>,
}

pub struct SubmitParams {
    pub task: String,
    pub spec: TaskSpec,
    pub answers: Vec<RuleAnswer>,
    pub verify_manual: bool,
    pub author: Author,
}

/// Registra uma verificação. Regras com script atual são decididas rodando o script (respostas a elas são
/// ignoradas). As demais só valem se respondidas; com `verify_manual` todas precisam de resposta, senão as
/// sem resposta ficam `pending`. Passa quando nenhuma `must` falhou (falhas `should` e testes desatualizados
/// viram avisos).
pub fn submit_check(
    store: &Store,
    params: &SubmitParams,
    runner: &RuleTestRunner,
) -> Result<RuleCheck> {
    submit_check_with(store, params, runner, &RunOptions::default(), &|_| {})
}

/// Como `submit_check`, com opções de execução (cancelamento) e eventos por script (progresso). Cancelado
/// durante os scripts, nada é gravado e o resultado é `RuleError::Cancelled`.
pub fn submit_check_with(
    store: &Store,
    params: &SubmitParams,
    runner: &RuleTestRunner,
    opts: &RunOptions,
    on_event: &(dyn Fn(RuleScriptEvent) + Sync),
) -> Result<RuleCheck> {
    let scope = task_scope(store, &params.spec)?;
    let cands = candidates(&scope.topics);

    let mut answered: HashMap<Id, RuleResult> = HashMap::new();
    for answer in &params.answers {
        let at = match_rule(&answer.rule_id, cands.iter().map(|(_, r)| r))?;
        let (slug, rule) = &cands[at];
        if !rule.test_state().needs_agent() {
            continue;
        }
        answered.insert(
            rule.id,
            RuleResult {
                topic: slug.clone(),
                rule_id: rule.id,
                verdict: answer.verdict,
                note: answer.note.as_deref().and_then(trimmed_non_empty),
                source: RuleResultSource::Agent,
                exit_code: None,
            },
        );
    }
    let missing: Vec<String> = cands
        .iter()
        .filter(|(_, r)| r.test_state().needs_agent() && !answered.contains_key(&r.id))
        .map(|(slug, r)| {
            format!(
                "[{slug}] {} {}",
                r.id.to_string().chars().take(8).collect::<String>(),
                r.text
            )
        })
        .collect();
    if !missing.is_empty() && params.verify_manual {
        return Err(RuleError::IncompleteCheck(missing));
    }
    // Todo script roda, mesmo depois de um `must` reprovado: o check responde a todas as regras.
    let runs = run_scripts(store.root(), &cands, &scope.files, runner, opts, on_event);
    if opts
        .cancellation
        .as_ref()
        .is_some_and(super::runner::Cancellation::is_cancelled)
    {
        return Err(RuleError::Cancelled);
    }
    for run in runs {
        answered.insert(
            run.rule.id,
            RuleResult {
                topic: run.topic.clone(),
                rule_id: run.rule.id,
                verdict: run.outcome.verdict,
                note: Some(
                    format!(
                        "{} (exit {})\n{}",
                        run.command, run.outcome.exit_code, run.outcome.output
                    )
                    .trim()
                    .to_string(),
                ),
                source: RuleResultSource::Script,
                exit_code: Some(run.outcome.exit_code),
            },
        );
    }
    save_rule_check(
        store,
        &params.task,
        scope.files,
        &scope.topics,
        scope.item,
        &answered,
        params.author,
    )
}

fn save_rule_check(
    store: &Store,
    task: &str,
    files: Vec<String>,
    topics: &[Record<RuleTopic>],
    item: Option<Id>,
    answered: &HashMap<Id, RuleResult>,
    author: Author,
) -> Result<RuleCheck> {
    let cands = candidates(topics);
    let failed: Vec<&Rule> = cands
        .iter()
        .map(|(_, r)| r)
        .filter(|r| {
            answered
                .get(&r.id)
                .is_some_and(|a| a.verdict == RuleVerdict::Fail)
        })
        .collect();
    let stale = cands
        .iter()
        .map(|(_, r)| r)
        .filter(|r| r.test_state() == super::rule::RuleTestState::Stale)
        .map(|r| format!("Teste desatualizado (a regra mudou): {}", r.text));
    let pending: Vec<String> = cands
        .iter()
        .map(|(_, r)| r)
        .filter(|r| r.test_state().needs_agent() && !answered.contains_key(&r.id))
        .map(|r| r.text.clone())
        .collect();
    let mut warnings: Vec<String> = failed
        .iter()
        .filter(|r| r.severity == RuleSeverity::Should)
        .map(|r| r.text.clone())
        .collect();
    warnings.extend(stale);
    let failures: Vec<String> = failed
        .iter()
        .filter(|r| r.severity == RuleSeverity::Must)
        .map(|r| r.text.clone())
        .collect();
    let check = RuleCheck {
        schema: Some(schema_url("rule-check")),
        id: Id::new(),
        task: task.to_string(),
        files,
        topics: topics.iter().map(|t| t.slug.clone()).collect(),
        review_item: item,
        results: cands
            .iter()
            .filter_map(|(_, r)| answered.get(&r.id).cloned())
            .collect(),
        passed: failures.is_empty(),
        warnings,
        failures,
        pending,
        author,
        created_at: TimestampMs::now(),
    };
    store.ensure_directories()?;
    store.save_check(&check)?;
    Ok(check)
}

/// Executa um instantâneo fixo (a UI), em vez de recarregar as regras entre fases.
pub fn run_rule_scripts(
    store: &Store,
    snapshot: &[Record<RuleTopic>],
    runner: &RuleTestRunner,
    opts: &RunOptions,
    on_event: &(dyn Fn(RuleScriptEvent) + Sync),
) -> Vec<RuleTestRun> {
    run_scripts(
        store.root(),
        &candidates(snapshot),
        &[],
        runner,
        opts,
        on_event,
    )
}

/// Grava uma verificação completa da UI sem rodar os scripts de novo; exige que as regras não tenham mudado.
pub fn complete_rule_execution(
    store: &Store,
    snapshot: &[Record<RuleTopic>],
    results: &[RuleResult],
) -> Result<RuleCheck> {
    for entry in snapshot {
        if load_topic(store, &entry.slug)? != entry.value {
            return Err(RuleError::ExecutionChanged);
        }
    }
    let cands = candidates(snapshot);
    let distinct: std::collections::HashSet<Id> = results.iter().map(|r| r.rule_id).collect();
    let complete = results.len() == cands.len()
        && distinct.len() == results.len()
        && cands.iter().all(|(slug, rule)| {
            let expected = if rule.script_command().is_none() {
                RuleResultSource::Agent
            } else {
                RuleResultSource::Script
            };
            results
                .iter()
                .any(|r| r.rule_id == rule.id && &r.topic == slug && r.source == expected)
        });
    if !complete {
        return Err(RuleError::ExecutionIncomplete);
    }
    let answered: HashMap<Id, RuleResult> =
        results.iter().map(|r| (r.rule_id, r.clone())).collect();
    save_rule_check(
        store,
        "Verificação de regras pelo aplicativo",
        vec![],
        snapshot,
        None,
        &answered,
        Author::Ai,
    )
}

/// Todos os checks gravados, do mais novo ao mais antigo.
pub fn list_checks(store: &Store) -> Result<Vec<RuleCheck>> {
    Ok(store.checks()?.into_iter().map(|r| r.check).collect())
}

/// Tópicos que seguram um item de revisão: `rules` explícitas + os que casam `target.file` + globais.
pub fn required_topics(store: &Store, item: &ReviewItem) -> Result<Vec<Record<RuleTopic>>> {
    let files: Vec<String> = item
        .target
        .as_ref()
        .and_then(|t| t.file.clone())
        .into_iter()
        .collect();
    applicable_topics(store, &files, &item.rules)
}

/// Por que o item não pode ir a `done` (vazio = verificado): o último check do item precisa ter passado e
/// respondido toda regra atual dos tópicos exigidos.
pub fn verification_problems(store: &Store, item: &ReviewItem) -> Result<Vec<String>> {
    let required = required_topics(store, item)?;
    let rules = candidates(&required);
    if rules.is_empty() {
        return Ok(vec![]);
    }
    let checks = list_checks(store)?;
    let Some(check) = checks.iter().find(|c| c.review_item == Some(item.id)) else {
        return Ok(vec![format!(
            "Nenhum check registrado para este item (tópicos: {}).",
            required
                .iter()
                .map(|t| t.slug.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        )]);
    };
    if !check.passed {
        return Ok(check
            .failures
            .iter()
            .map(|f| format!("Falhou no último check: {f}"))
            .collect());
    }
    let answered: std::collections::HashSet<Id> = check.results.iter().map(|r| r.rule_id).collect();
    Ok(rules
        .iter()
        .filter(|(_, r)| !answered.contains(&r.id))
        .filter_map(|(slug, rule)| {
            if !rule.test_state().needs_agent() {
                return Some(format!("Regra nova desde o último check: [{slug}] {}", rule.text));
            }
            // Check só de scripts deixa as manuais sem verificar: só as obrigatórias seguram o item.
            (rule.severity == RuleSeverity::Must).then(|| {
                format!(
                    "Regra manual obrigatória sem verificação: [{slug}] {} (envie o check com as regras manuais respondidas)",
                    rule.text
                )
            })
        })
        .collect())
}

/// `rulesNotVerified` a menos que o item possa ser marcado como concluído.
pub fn ensure_verified(store: &Store, item_reference: &str) -> Result<()> {
    let item = find_review_item(store, item_reference)?;
    let problems = verification_problems(store, &item)?;
    if problems.is_empty() {
        Ok(())
    } else {
        Err(RuleError::RulesNotVerified(problems))
    }
}

#[allow(dead_code)]
fn _all_topics(store: &Store) -> Result<Vec<Record<RuleTopic>>> {
    list_topics(store)
}
