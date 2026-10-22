//! Tools MCP — Workflows e execuções (runs) (mcp.md §4.8).

use serde::Serialize;
use serde_json::{Value, json};
use vibedeck_core::model::{AiProvider, NextStepKind, WorkflowRunStatus};
use vibedeck_core::workflows::{
    self as wf, WorkflowError, WorkflowQuestionDraft, orchestrator_prompt,
};

use crate::mcp::args::Args;
use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text};

impl From<WorkflowError> for ToolError {
    fn from(e: WorkflowError) -> Self {
        ToolError(e.to_string())
    }
}

const RUN: (&str, &str) = ("string", "workflow/execução|id");
const STEP_KINDS: &[&str] = &["agent", "command", "skill"];

fn run_prop() -> crate::mcp::schema::Prop {
    prop("run", RUN.0, RUN.1)
}

/// JSON do valor com `slug` junto (`SlugAnd`).
fn slug_and<T: Serialize>(slug: &str, value: &T) -> Result<String, ToolError> {
    let mut v = serde_json::to_value(value).map_err(|e| ToolError(e.to_string()))?;
    if let Some(o) = v.as_object_mut() {
        o.insert("slug".into(), json!(slug));
    }
    json_text(&v)
}

fn provider_of(args: &Args) -> Result<Option<AiProvider>, ToolError> {
    if args.str("provider").is_none() {
        return Ok(None);
    }
    Ok(Some(match args.provider()? {
        "codex" => AiProvider::Codex,
        _ => AiProvider::Claude,
    }))
}

fn questions_schema() -> Value {
    json!({
        "type": "array",
        "description": "2 a 4 opções cada, recomendada primeiro.",
        "items": {
            "type": "object",
            "properties": {
                "question": {"type": "string"},
                "context": {"type": "string"},
                "options": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {"label": {"type": "string"}, "description": {"type": "string"}},
                        "required": ["label"]
                    }
                },
                "multiple": {"type": "boolean"}
            },
            "required": ["question"]
        }
    })
}

#[derive(Serialize)]
struct WorkflowRow<'a> {
    slug: &'a str,
    title: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    summary: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    input: Option<&'a str>,
    tags: &'a [String],
    steps: Vec<&'a str>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunRow<'a> {
    r#ref: &'a str,
    workflow: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    input: Option<&'a str>,
    status: WorkflowRunStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    current: Option<&'a str>,
    steps: usize,
    open_questions: usize,
    updated_at: vibedeck_core::model::Timestamp,
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "list_workflows",
            "",
            schema(&[], &[], &[], &[]),
            |ctx: &ToolCtx, _: &Args| {
                let store = ctx.store()?;
                let list = wf::list_workflows(&store)?;
                let rows: Vec<WorkflowRow> = list
                    .iter()
                    .map(|r| WorkflowRow {
                        slug: &r.slug,
                        title: &r.value.title,
                        summary: r.value.summary.as_deref(),
                        input: r.value.input.as_deref(),
                        tags: &r.value.tags,
                        steps: r.value.steps.iter().map(|s| s.id.as_str()).collect(),
                    })
                    .collect();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "get_workflow",
            "",
            schema(&[prop("workflow", "string", "")], &["workflow"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let slug = wf::resolve_workflow_slug(&store, args.req("workflow")?)?;
                slug_and(&slug, &wf::load_workflow(&store, &slug)?)
            },
        )
        .read_only(),
        Tool::new(
            "add_workflow",
            "Workflow vazio; complete com add_workflow_step/add_workflow_transition.",
            schema(
                &[
                    prop("title", "string", ""),
                    prop("summary", "string", ""),
                    prop("input", "string", "O que pedir ao iniciar"),
                    prop("max_steps", "integer", "Etapas por execução (padrão 25)"),
                    prop("tags", "array", ""),
                ],
                &["title"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let rec = wf::create_workflow(
                    &store,
                    args.req("title")?,
                    args.str("summary").map(str::to_string),
                    args.str("input").map(str::to_string),
                    args.int("max_steps").filter(|n| *n > 0),
                    args.list("tags").unwrap_or_default(),
                    ctx.author(args)?,
                )?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "update_workflow",
            "",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("title", "string", ""),
                    prop("summary", "string", ""),
                    prop("input", "string", ""),
                    prop("max_steps", "integer", "0 = padrão"),
                    prop("tags", "array", ""),
                ],
                &["workflow"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let tags = args.list("tags");
                let max_steps = args.int("max_steps");
                let rec = wf::update_workflow(&store, args.req("workflow")?, |w| {
                    if let Some(t) = args.str("title") {
                        w.title = t.to_string();
                    }
                    if let Some(v) = args.str("summary") {
                        w.summary = Some(v.to_string());
                    }
                    if let Some(v) = args.str("input") {
                        w.input = Some(v.to_string());
                    }
                    if let Some(m) = max_steps {
                        w.max_steps = (m > 0).then_some(m);
                    }
                    if let Some(t) = tags {
                        w.tags = t;
                    }
                    Ok(())
                })?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "add_workflow_step",
            "Adiciona uma etapa (a primeira é o início) e devolve o id.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("target", "string", ""),
                    prop("kind", "string", ""),
                    prop("note", "string", "Instrução extra ($ARGUMENTS em comandos)"),
                    prop("max_visits", "integer", "Por ciclo"),
                ],
                &["workflow", "target"],
                &[("kind", STEP_KINDS)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let kind = match args.str("kind") {
                    None => NextStepKind::Agent,
                    Some("agent") => NextStepKind::Agent,
                    Some("command") => NextStepKind::Command,
                    Some("skill") => NextStepKind::Skill,
                    Some(k) => {
                        return Err(ToolError::invalid_params(format!("Tipo inválido: {k}")));
                    }
                };
                let (mut rec, step) = wf::add_workflow_step(
                    &store,
                    args.req("workflow")?,
                    kind,
                    args.req("target")?,
                    args.str("note"),
                )?;
                if let Some(visits) = args.int("max_visits") {
                    rec = wf::set_workflow_step_max_visits(&store, &rec.slug, &step, Some(visits))?;
                }
                let mut v = serde_json::to_value(json!({"slug": rec.slug, "step": step}))
                    .map_err(|e| ToolError(e.to_string()))?;
                v["workflow"] =
                    serde_json::to_value(&rec.value).map_err(|e| ToolError(e.to_string()))?;
                json_text(&v)
            },
        ),
        Tool::new(
            "set_workflow_step_max_visits",
            "Limite de execuções da etapa por ciclo; estourar para a execução.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("step", "string", "Id ou posição"),
                    prop("max_visits", "integer", "0 = sem limite"),
                ],
                &["workflow", "step", "max_visits"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let Some(visits) = args.int("max_visits") else {
                    return Err(ToolError::invalid_params(
                        "Parâmetro obrigatório: max_visits",
                    ));
                };
                let rec = wf::set_workflow_step_max_visits(
                    &store,
                    args.req("workflow")?,
                    args.req("step")?,
                    Some(visits),
                )?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "remove_workflow_step",
            "Remove uma etapa e as transições para ela.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("step", "string", "Id ou posição"),
                ],
                &["workflow", "step"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let rec =
                    wf::remove_workflow_step(&store, args.req("workflow")?, args.req("step")?)?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "move_workflow_step",
            "Move uma etapa (1 = início).",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("step", "string", "Id ou posição"),
                    prop("position", "integer", ""),
                ],
                &["workflow", "step", "position"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let Some(position) = args.int("position") else {
                    return Err(ToolError::invalid_params("Parâmetro obrigatório: position"));
                };
                let rec = wf::move_workflow_step(
                    &store,
                    args.req("workflow")?,
                    args.req("step")?,
                    position,
                )?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "add_workflow_transition",
            "Prioridade: verdict, when, senão (sem ambos, único por etapa); nenhuma transição = fim.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("from", "string", "Id ou posição"),
                    prop("to", "string", "Id ou posição"),
                    prop("verdict", "string", "Ex.: APROVADO; ignora caixa e acentos"),
                    prop("when", "string", "Condição textual"),
                ],
                &["workflow", "from", "to"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let rec = wf::add_workflow_transition(
                    &store,
                    args.req("workflow")?,
                    args.req("from")?,
                    args.req("to")?,
                    args.str("when"),
                    args.str("verdict"),
                )?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "remove_workflow_transition",
            "Remove a transição `index` (1, 2, …) de uma etapa.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("from", "string", "Id ou posição"),
                    prop("index", "integer", ""),
                ],
                &["workflow", "from", "index"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let Some(index) = args.int("index") else {
                    return Err(ToolError::invalid_params("Parâmetro obrigatório: index"));
                };
                let rec = wf::remove_workflow_transition(
                    &store,
                    args.req("workflow")?,
                    args.req("from")?,
                    index,
                )?;
                slug_and(&rec.slug, &rec.value)
            },
        ),
        Tool::new(
            "workflow_flow",
            "JSON do workflow para orquestrar; siga as `rules` dele.",
            schema(
                &[
                    prop("workflow", "string", ""),
                    prop("input", "string", "Sem ela, pergunte ao usuário"),
                ],
                &["workflow"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let plan = wf::workflow_plan(&store, args.req("workflow")?, args.str("input"))?;
                plan.json().map_err(|e| ToolError(e.to_string()))
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_start",
            "Retorna {ref,action,prompt}; siga prompt em subagentes. from permite outra volta em execução parada.",
            schema(
                &[
                    prop("provider", "string", "claude (padrão)|codex"),
                    prop("workflow", "string", ""),
                    prop("input", "string", "Nomeia a execução"),
                    prop("from", "string", "Etapa inicial"),
                ],
                &["workflow"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let provider = provider_of(args)?;
                let (reference, run, action) = wf::start_run(
                    &store,
                    args.req("workflow")?,
                    args.str("input"),
                    args.str("from"),
                    provider,
                )?;
                let title = wf::load_workflow(&store, &run.workflow)
                    .map(|w| w.title)
                    .unwrap_or_else(|_| run.workflow.clone());
                let prompt = orchestrator_prompt(
                    &reference,
                    &title,
                    run.input.as_deref(),
                    "vibedeck",
                    run.provider,
                );
                json_text(&json!({"ref": reference, "action": action, "prompt": prompt}))
            },
        ),
        Tool::new(
            "workflow_run_next",
            "Próxima ação: run-step, ask, decide, done ou stop.",
            schema(&[run_prop()], &["run"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                json_text(&wf::next_run_action(&store, args.req("run")?)?)
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_step",
            "Prompt da etapa atual, para o subagente que a executa.",
            schema(&[run_prop()], &["run"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                Ok(wf::run_step_prompt(&store, args.req("run")?, "vibedeck")?)
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_record",
            "Próxima ação após veredito. Em decide, avalie candidates e reenvie to ou none_holds.",
            schema(
                &[
                    run_prop(),
                    prop("verdict", "string", "Última linha do resultado"),
                    prop("summary", "string", "1 a 3 linhas"),
                    prop("to", "string", ""),
                    prop("none_holds", "boolean", ""),
                ],
                &["run"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                json_text(&wf::record_run(
                    &store,
                    args.req("run")?,
                    args.str("verdict"),
                    args.str("summary"),
                    args.str("to"),
                    args.bool("none_holds").unwrap_or(false),
                )?)
            },
        ),
        Tool::new(
            "workflow_run_ask",
            "Grava perguntas ao usuário; termine a etapa com PERGUNTA na última linha.",
            schema(
                &[run_prop()],
                &["run", "questions"],
                &[],
                &[("questions", questions_schema())],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let Some(raw) = args.raw("questions") else {
                    return Err(ToolError::invalid_params(
                        "Parâmetro obrigatório: questions",
                    ));
                };
                let parsed: Result<Vec<WorkflowQuestionDraft>, serde_json::Error> = match raw {
                    Value::String(text) => serde_json::from_str(text),
                    other => serde_json::from_value(other.clone()),
                };
                let drafts = parsed.map_err(|_| {
                    ToolError::invalid_params(
                        "questions deve ser uma lista de {question, context, options: [{label, description}], multiple}.",
                    )
                })?;
                let added = wf::ask_run(&store, args.req("run")?, &drafts)?;
                let numbers: Vec<String> = added.iter().map(|q| q.number.to_string()).collect();
                Ok(format!(
                    "Pergunta(s) gravada(s): {}. Termine a etapa com a última linha: PERGUNTA",
                    numbers.join(", ")
                ))
            },
        ),
        Tool::new(
            "workflow_run_questions",
            "",
            schema(
                &[run_prop(), prop("open", "boolean", "Só as abertas")],
                &["run"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = wf::resolve_run_ref(&store, args.req("run")?)?;
                let run = wf::load_run(&store, &reference)?;
                let open = args.bool("open").unwrap_or(false);
                let list: Vec<_> = run
                    .questions
                    .iter()
                    .filter(|q| !open || q.is_open())
                    .collect();
                json_text(&list)
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_answer",
            "Grava a resposta do usuário (opções separadas por \"; \" ou texto) e devolve a próxima ação.",
            schema(
                &[
                    run_prop(),
                    prop("number", "integer", ""),
                    prop("answer", "string", ""),
                ],
                &["run", "number", "answer"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let Some(number) = args.int("number") else {
                    return Err(ToolError::invalid_params("Parâmetro obrigatório: number"));
                };
                json_text(&wf::answer_run(
                    &store,
                    args.req("run")?,
                    number,
                    args.req("answer")?,
                )?)
            },
        ),
        Tool::new(
            "workflow_run_list",
            "",
            schema(
                &[prop("workflow", "string", ""), prop("status", "string", "")],
                &[],
                &[("status", &["running", "waiting", "done", "stopped"])],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let status = args.str("status").and_then(|s| match s {
                    "running" => Some(WorkflowRunStatus::Running),
                    "waiting" => Some(WorkflowRunStatus::Waiting),
                    "done" => Some(WorkflowRunStatus::Done),
                    "stopped" => Some(WorkflowRunStatus::Stopped),
                    _ => None,
                });
                let runs = wf::list_runs(&store, args.str("workflow"))?;
                let rows: Vec<RunRow> = runs
                    .iter()
                    .filter(|r| status.is_none_or(|s| r.run.status == s))
                    .map(|r| RunRow {
                        r#ref: &r.reference,
                        workflow: &r.run.workflow,
                        input: r.run.input.as_deref(),
                        status: r.run.status,
                        current: r.run.current.as_deref(),
                        steps: r.run.history.len(),
                        open_questions: r.run.open_questions().len(),
                        updated_at: r.run.updated_at,
                    })
                    .collect();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_show",
            "",
            schema(&[run_prop()], &["run"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = wf::resolve_run_ref(&store, args.req("run")?)?;
                json_text(&wf::load_run(&store, &reference)?)
            },
        )
        .read_only(),
        Tool::new(
            "workflow_run_stop",
            "Para uma execução. Só a pedido do usuário.",
            schema(
                &[run_prop(), prop("reason", "string", "")],
                &["run"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                json_text(&wf::stop_run(&store, args.req("run")?, args.str("reason"))?)
            },
        ),
    ]
}
