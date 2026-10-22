//! Tools MCP — Regras: tópicos, rules_for, runner de scripts, checks e testes de regra (mcp.md §4.4).

use crate::mcp::args::Args;
use crate::mcp::schema::{Prop, prop, schema};
use crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text};
use serde::Serialize;
use serde_json::{Value, json};
use std::sync::atomic::{AtomicU64, Ordering};
use vibedeck_core::model::{Rule, RuleSeverity, RuleTestMode, RuleVerdict};
use vibedeck_core::rules::{
    self, RuleAnswer, RuleError, RuleExt, RuleScriptEvent, RuleTestRunRow, RuleTestRunner,
    RunOptions, SubmitParams, TaskSpec, TopicChecklist,
};

impl From<RuleError> for ToolError {
    fn from(e: RuleError) -> Self {
        ToolError(e.to_string())
    }
}

#[derive(Serialize)]
struct TopicRow {
    slug: String,
    title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    tags: Vec<String>,
    paths: Vec<String>,
    rules: usize,
}

fn results_schema() -> Value {
    json!({
        "type": "array",
        "description": "Só com verify_manual=true: uma resposta por regra manual.",
        "items": {
            "type": "object",
            "properties": {
                "ruleId": {"type": "string", "description": "Id ou prefixo >= 4"},
                "verdict": {"type": "string", "enum": ["pass", "fail", "na"]},
                "note": {"type": "string", "description": "Evidência"},
            },
            "required": ["ruleId", "verdict"],
        },
    })
}

/// Opções de execução desta chamada (cancelamento por `notifications/cancelled`) e o ouvinte que emite
/// `notifications/progress` por script (`ruleId`, `state`, `output`) quando o cliente pediu progresso.
fn execution(ctx: &ToolCtx) -> (RunOptions, impl Fn(RuleScriptEvent) + Sync + use<>) {
    let options = RunOptions {
        cancellation: Some(ctx.cancel.clone()),
        ..RunOptions::default()
    };
    let ctx = ctx.clone();
    let counter = AtomicU64::new(0);
    let listener = move |event: RuleScriptEvent| {
        let (topic, rule_id, state, output) = match event {
            RuleScriptEvent::Started { topic, rule, .. } => {
                (topic, rule.id.to_string(), "running", String::new())
            }
            RuleScriptEvent::Finished { run, .. } => {
                let state = match run.outcome.verdict {
                    RuleVerdict::Pass => "pass",
                    RuleVerdict::Fail => "fail",
                    RuleVerdict::Na => "na",
                };
                (
                    run.topic,
                    run.rule.id.to_string(),
                    state,
                    run.outcome.output,
                )
            }
        };
        let detail = json!({"ruleId": rule_id, "state": state, "output": output, "topic": topic});
        ctx.report_progress(
            counter.fetch_add(1, Ordering::SeqCst) + 1,
            &detail.to_string(),
            detail,
        );
    };
    (options, listener)
}

fn id8(id: &impl ToString) -> String {
    id.to_string().chars().take(8).collect()
}

pub fn tools() -> Vec<Tool> {
    let p = |name, ty, d| -> Prop { prop(name, ty, d) };
    vec![
        Tool::new(
            "rules_for",
            "OBRIGATÓRIO antes de concluir uma tarefa. Manuais contadas sem include_manual.",
            schema(
                &[
                    p("files", "array", "Arquivos alterados"),
                    p("topics", "array", "Tópicos extras"),
                    p("review_item", "string", ""),
                    p("include_manual", "boolean", "Lista as manuais com detalhes"),
                    p("verbose", "boolean", "Forma completa"),
                ],
                &[],
                &[],
                &[],
            ),
            rules_for,
        )
        .read_only(),
        Tool::new(
            "submit_rule_check",
            "Scripts; manuais pending. Com verify_manual=true, responda TODAS as manuais em results. passed=false: corrija e reenvie. Resumo; completo em disco.",
            schema(
                &[
                    p("task", "string", "Resumo do que foi feito"),
                    p("files", "array", ""),
                    p("topics", "array", "Os mesmos do rules_for"),
                    p("review_item", "string", ""),
                    p("verify_manual", "boolean", ""),
                    p("verbose", "boolean", "Anexa o JSON completo"),
                ],
                &["task"],
                &[],
                &[("results", results_schema())],
            ),
            submit_rule_check,
        ),
        Tool::new(
            "run_rule_tests",
            "Scripts sem check (0 cumpre, 77 n/a, outro viola); sem files/review_item, só topics.",
            schema(
                &[
                    p("files", "array", ""),
                    p("topics", "array", ""),
                    p("review_item", "string", ""),
                ],
                &[],
                &[],
                &[],
            ),
            run_rule_tests,
        )
        .read_only(),
        Tool::new(
            "set_rule_test",
            "Define script (raiz, $VIBEDECK_FILES, exit 0/77/outro) ou manual; editar regra desatualiza teste.",
            schema(
                &[
                    p("rule_id", "string", ""),
                    p("mode", "string", ""),
                    p("command", "string", "Obrigatório em script"),
                    p("reason", "string", ""),
                ],
                &["rule_id", "mode"],
                &[("mode", &["script", "manual"])],
                &[],
            ),
            set_rule_test,
        ),
        Tool::new(
            "list_rule_topics",
            "",
            schema(&[], &[], &[], &[]),
            list_rule_topics,
        )
        .read_only(),
        Tool::new(
            "get_rule_topic",
            "",
            schema(&[p("topic", "string", "")], &["topic"], &[], &[]),
            get_rule_topic,
        )
        .read_only(),
        Tool::new(
            "add_rule_topic",
            "Sem paths: global.",
            schema(
                &[
                    p("title", "string", ""),
                    p("description", "string", "Quando se aplica"),
                    p("paths", "array", "Globs"),
                    p("tags", "array", ""),
                ],
                &["title"],
                &[],
                &[],
            ),
            add_rule_topic,
        ),
        Tool::new(
            "add_rule",
            "author=ai; tópico automático.",
            schema(
                &[
                    p("topic", "string", ""),
                    p("text", "string", "Curta e verificável"),
                    p("details", "string", "Como verificar"),
                    p("severity", "string", "must bloqueia; should avisa"),
                ],
                &["topic", "text"],
                &[("severity", &["must", "should"])],
                &[],
            ),
            add_rule,
        ),
    ]
}

fn list_or_empty(args: &Args, key: &str) -> Vec<String> {
    args.list(key).unwrap_or_default()
}

fn rules_for(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let mut files = list_or_empty(args, "files");
    let mut topics = list_or_empty(args, "topics");
    if let Some(reference) = args.str("review_item") {
        let item = rules::find_review_item(&store, reference)?;
        topics.extend(item.rules.iter().cloned());
        if let Some(file) = item.target.as_ref().and_then(|t| t.file.clone()) {
            files.push(file);
        }
    }
    let applicable = rules::applicable_topics(&store, &files, &topics)?;
    if applicable.iter().all(|t| t.value.rules.is_empty()) {
        return Ok("Nenhuma regra aplicável a esses arquivos. Mesmo assim, chame submit_rule_check com results=[] para registrar a tarefa.".to_string());
    }
    let include_manual = args.bool("include_manual").unwrap_or(false);
    if args.bool("verbose") == Some(true) {
        let rows: Vec<TopicChecklist> = applicable
            .iter()
            .map(|t| TopicChecklist::new(&t.slug, &t.value, include_manual))
            .collect();
        return json_text(&rows);
    }
    Ok(TopicChecklist::compact_json(&TopicChecklist::compact(
        &applicable,
        include_manual,
    ))?)
}

fn submit_rule_check(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let mut answers: Vec<RuleAnswer> = Vec::new();
    if let Some(raw) = args.raw("results") {
        let decoded = match raw {
            Value::String(text) => serde_json::from_str(text),
            other => serde_json::from_value(other.clone()),
        };
        answers = decoded.map_err(|_| {
            ToolError::invalid_params(
                "results deve ser uma lista de {ruleId, verdict: pass|fail|na, note}.",
            )
        })?;
    }
    let (options, listener) = execution(ctx);
    let check = rules::submit_check_with(
        &store,
        &SubmitParams {
            task: args.req("task")?.to_string(),
            spec: TaskSpec {
                files: list_or_empty(args, "files"),
                topics: list_or_empty(args, "topics"),
                review_item: args.str("review_item").map(str::to_string),
            },
            answers,
            verify_manual: args.bool("verify_manual").unwrap_or(false),
            author: vibedeck_core::model::Author::Ai,
        },
        &RuleTestRunner::live(),
        &options,
        &listener,
    )?;
    Ok(rules::agent_summary(
        &check,
        args.bool("verbose").unwrap_or(false),
    )?)
}

fn run_rule_tests(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let files = list_or_empty(args, "files");
    let item = args.str("review_item").map(str::to_string);
    let only_topics = files.is_empty() && item.is_none();
    let spec = TaskSpec {
        files,
        topics: list_or_empty(args, "topics"),
        review_item: item,
    };
    let (options, listener) = execution(ctx);
    let runs = rules::run_rule_tests_with(
        &store,
        &spec,
        only_topics,
        &RuleTestRunner::live(),
        &options,
        &listener,
    )?;
    if ctx.cancel.is_cancelled() {
        return Err(RuleError::Cancelled.into());
    }
    if runs.is_empty() {
        return Ok("Nenhuma regra aplicável tem script.".to_string());
    }
    let rows: Vec<RuleTestRunRow> = runs.iter().map(RuleTestRunRow::from).collect();
    json_text(&rows)
}

fn set_rule_test(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let mode = match args.req("mode")? {
        "script" => RuleTestMode::Script,
        "manual" => RuleTestMode::Manual,
        _ => return Err(ToolError::invalid_params("mode deve ser script ou manual.")),
    };
    let rule = rules::set_rule_test(
        &store,
        args.req("rule_id")?,
        mode,
        args.str("command"),
        args.str("reason"),
    )?;
    Ok(format!(
        "Regra {}: {}.",
        id8(&rule.id),
        rule.test_state().label()
    ))
}

fn list_rule_topics(ctx: &ToolCtx, _args: &Args) -> Result<String, ToolError> {
    let rows: Vec<TopicRow> = rules::list_topics(&ctx.store()?)?
        .into_iter()
        .map(|t| TopicRow {
            slug: t.slug,
            title: t.value.title,
            description: t.value.description,
            tags: t.value.tags,
            paths: t.value.paths,
            rules: t.value.rules.len(),
        })
        .collect();
    json_text(&rows)
}

fn get_rule_topic(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let slug = rules::resolve_topic_slug(&store, args.req("topic")?)?;
    let topic = rules::load_topic(&store, &slug)?;
    json_text(&TopicChecklist::new(&slug, &topic, true))
}

fn add_rule_topic(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let created = rules::create_topic(
        &store,
        args.req("title")?,
        args.str("description").map(str::to_string),
        list_or_empty(args, "tags"),
        list_or_empty(args, "paths"),
        vec![],
    )?;
    json_text(&TopicChecklist::new(&created.slug, &created.value, true))
}

fn add_rule(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let mut rule = Rule::new(args.req("text")?);
    rule.details = args.str("details").map(str::to_string);
    rule.severity = if args.severity()? == "should" {
        RuleSeverity::Should
    } else {
        RuleSeverity::Must
    };
    rule.author = ctx.author(args)?;
    let (slug, saved) = rules::add_rule(&store, rule, args.req("topic")?)?;
    json_text(&json!({"topic": slug, "ruleId": saved.id.to_string(), "text": saved.text}))
}
