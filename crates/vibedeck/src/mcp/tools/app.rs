//! Tools MCP extras do modo `vibedeck mcp --app` (aplicativo macOS). Fora do catálogo padrão para não pesar
//! no contexto dos agentes de IA: o app as pede com `--app` e elas substituem as de mesmo nome.

use std::collections::HashSet;

use serde_json::{Value, json};
use vibedeck_core::app::{self, AppError, RecordKind};
use vibedeck_core::docs::{self, DocInfo};
use vibedeck_core::model::AiProvider;
use vibedeck_core::{rules, workflows};

use crate::mcp::args::Args;
use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

impl From<AppError> for ToolError {
    fn from(e: AppError) -> Self {
        ToolError(e.0)
    }
}

const KIND: &str = "reviews|rules|ideas|agents|commands|skills|workflows";

/// JSON como string (o conteúdo exato do arquivo) ou como objeto.
fn json_arg(args: &Args, key: &str) -> Result<String, ToolError> {
    match args.raw(key) {
        Some(Value::String(text)) if !text.is_empty() => Ok(text.clone()),
        Some(object @ Value::Object(_)) => Ok(object.to_string()),
        _ => Err(ToolError::invalid_params(format!(
            "Parâmetro obrigatório: {key}"
        ))),
    }
}

fn kind_arg(args: &Args) -> Result<RecordKind, ToolError> {
    Ok(RecordKind::parse(args.req("kind")?)?)
}

fn provider_arg(args: &Args) -> Result<Option<AiProvider>, ToolError> {
    if args.str("provider").is_none() {
        return Ok(None);
    }
    Ok(Some(match args.provider()? {
        "codex" => AiProvider::Codex,
        _ => AiProvider::Claude,
    }))
}

fn run_and_ref(reference: &str, run: &impl serde::Serialize) -> Result<String, ToolError> {
    json_text(&json!({"ref": reference, "run": run}))
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "put_record",
            "Grava o registro inteiro (JSON do arquivo) após validar o modelo; atômico; cria subpastas; preserva author.",
            schema(
                &[
                    prop("kind", "string", KIND),
                    prop("slug", "string", "Caminho grupo/slug, sem .json"),
                    prop("record", "string", "JSON exato do arquivo"),
                ],
                &["kind", "slug", "record"],
                &[("kind", &RecordKind::NAMES)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let slug = args.req("slug")?;
                app::put_record(&store, kind_arg(args)?, slug, &json_arg(args, "record")?)?;
                Ok(format!("Salvo: {slug}"))
            },
        ),
        Tool::new(
            "delete_record",
            "Tira o registro do projeto, deixando cópia em .vibedeck/.trash; rules solta ideias e padrões órfãos.",
            schema(
                &[prop("kind", "string", KIND), prop("slug", "string", "")],
                &["kind", "slug"],
                &[("kind", &RecordKind::NAMES)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let slug = args.req("slug")?;
                app::delete_record(&store, kind_arg(args)?, slug)?;
                Ok(format!("Removido: {slug}"))
            },
        ),
        Tool::new(
            "put_project",
            "Grava o vibedeck.json inteiro; mudança na stack atualiza o badge do README.",
            schema(&[prop("project", "string", "JSON do vibedeck.json")], &["project"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                Ok(match app::put_project(&store, &json_arg(args, "project")?)? {
                    Some(warning) => format!("Salvo: vibedeck.json\nAviso: {warning}"),
                    None => "Salvo: vibedeck.json".to_string(),
                })
            },
        ),
        Tool::new(
            "list_checks",
            "Histórico de checks de regras, do mais recente ao mais antigo.",
            schema(&[], &[], &[], &[]),
            |ctx, _| json_text(&rules::list_checks(&ctx.store()?)?),
        )
        .read_only(),
        Tool::new(
            "list_docs",
            "Docs com group, slug, title, tags e modified (ISO-8601), mais o vínculo quando houver.",
            schema(&[], &[], &[], &[]),
            |ctx, _| {
                let rows: Vec<Value> = docs::list_docs(&ctx.store()?)?
                    .iter()
                    .map(DocInfo::to_grouped_json)
                    .collect();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "delete_doc",
            "Apaga o doc (cópia em .vibedeck/.trash); em doc vinculado, só o vínculo.",
            schema(&[prop("slug", "string", "")], &["slug"], &[], &[]),
            |ctx, args| {
                let slug = app::delete_doc(&ctx.store()?, args.req("slug")?)?;
                Ok(format!("Removido: {slug}"))
            },
        ),
        Tool::new(
            "workflow_run_delete",
            "Apaga a execução e tudo que as etapas gravaram nela.",
            schema(&[prop("run", "string", "workflow/execução|id")], &["run"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = workflows::resolve_run_ref(&store, args.req("run")?)?;
                workflows::delete_run(&store, &reference)?;
                Ok(format!("Removido: {reference}"))
            },
        ),
        Tool::new(
            "workflow_run_checkpoint",
            "Grava a saída parcial da etapa em andamento (completed=false se foi interrompida).",
            schema(
                &[
                    prop("run", "string", "workflow/execução|id"),
                    prop("step", "string", "Etapa atual"),
                    prop("output", "string", ""),
                    prop("completed", "boolean", "Etapa terminou; senão foi interrompida"),
                    prop("verdict", "string", "Última linha, quando a etapa terminou"),
                ],
                &["run", "step"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = app::run_checkpoint(
                    &store,
                    args.req("run")?,
                    args.req("step")?,
                    args.str("verdict"),
                    args.str("output").unwrap_or(""),
                    args.bool("completed").unwrap_or(false),
                )?;
                Ok(format!("Salvo: {reference}"))
            },
        ),
        Tool::new(
            "workflow_run_save_output",
            "Grava a saída completa de uma etapa na pasta da execução e devolve o texto de referência.",
            schema(
                &[
                    prop("run", "string", "workflow/execução|id"),
                    prop("output", "string", ""),
                ],
                &["run", "output"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                Ok(workflows::save_run_output(
                    &store,
                    args.req("run")?,
                    args.req("output")?,
                )?)
            },
        ),
        Tool::new(
            "workflow_run_resume",
            "Retoma uma execução parada na etapa atual; devolve {ref, run}.",
            schema(&[prop("run", "string", "workflow/execução|id")], &["run"], &[], &[]),
            |ctx, args| {
                let (reference, run) = app::run_resume(&ctx.store()?, args.req("run")?)?;
                run_and_ref(&reference, &run)
            },
        ),
        Tool::new(
            "release_orphaned",
            "Solta ideias e padrões promovidos para tópico inexistente; devolve {ideas, patterns} soltos.",
            schema(&[], &[], &[], &[]),
            |ctx, _| json_text(&app::release_orphaned(&ctx.store()?)?),
        ),
        Tool::new(
            "workflow_run_restart",
            "Reinicia a execução (parada, em andamento ou terminada) da primeira etapa, em novo ciclo; devolve {ref, run}.",
            schema(&[prop("run", "string", "workflow/execução|id")], &["run"], &[], &[]),
            |ctx, args| {
                let (reference, run) = app::run_restart(&ctx.store()?, args.req("run")?)?;
                run_and_ref(&reference, &run)
            },
        ),
        Tool::new(
            "import_attachment",
            "Grava o arquivo (base64) como anexo de owner e devolve o link Markdown relativo.",
            schema(
                &[
                    prop("owner", "string", "Slug do doc ou da ideia dono do anexo"),
                    prop("name", "string", "Nome do arquivo, com extensão"),
                    prop("data_base64", "string", "Conteúdo em base64"),
                ],
                &["owner", "name", "data_base64"],
                &[],
                &[],
            ),
            |ctx, args| {
                let data = app::decode_base64(args.req("data_base64")?)?;
                Ok(app::import_attachment(
                    &ctx.store()?,
                    args.req("owner")?,
                    args.req("name")?,
                    &data,
                )?)
            },
        ),
        Tool::new(
            "rule_verification_status",
            "Por que o item de revisão não está verificado (problems vazio = verificado) e os tópicos exigidos.",
            schema(&[prop("review_item", "string", "")], &["review_item"], &[], &[]),
            |ctx, args| {
                json_text(&app::rule_verification_status(
                    &ctx.store()?,
                    args.req("review_item")?,
                )?)
            },
        )
        .read_only(),
        Tool::new(
            "project_revision",
            "Hash de caminhos, tamanhos e mtimes de vibedeck.json e .vibedeck; muda quando algo muda.",
            schema(&[], &[], &[], &[]),
            |ctx, _| json_text(&json!({"revision": app::revision(&ctx.root)})),
        )
        .read_only(),
        Tool::new(
            "reorganize_restore",
            "Desfaz (forward=false) ou refaz (forward=true) um recibo de reorganize_apply; falha se os arquivos mudaram.",
            schema(
                &[
                    prop("receipt", "string", "JSON devolvido por reorganize_apply"),
                    prop("forward", "boolean", "true refaz; false desfaz"),
                ],
                &["receipt", "forward"],
                &[],
                &[],
            ),
            |ctx, args| {
                let forward = args.bool("forward").ok_or_else(|| {
                    ToolError::invalid_params("Parâmetro obrigatório: forward")
                })?;
                app::reorganize_restore(&ctx.store()?, &json_arg(args, "receipt")?, forward)?;
                Ok(if forward { "Refeito." } else { "Desfeito." }.to_string())
            },
        ),
        Tool::new(
            "idea_implement",
            "Promove a ideia viável e, com workflow, cria/retoma (ou reinicia) a execução; devolve {topic, run_ref, prompt, run}.",
            schema(
                &[
                    prop("idea", "string", ""),
                    prop("workflow", "string", "Omita para a execução padrão"),
                    prop("restart", "boolean", "Reinicia a execução existente"),
                    prop("provider", "string", "claude (padrão)|codex"),
                    prop("skipping_paths", "array", "Globs da ideia a não copiar"),
                ],
                &["idea"],
                &[],
                &[],
            ),
            |ctx, args| {
                let skipping: HashSet<String> =
                    args.list("skipping_paths").unwrap_or_default().into_iter().collect();
                json_text(&app::idea_implement(
                    &ctx.store()?,
                    args.req("idea")?,
                    args.str("workflow"),
                    args.bool("restart").unwrap_or(false),
                    provider_arg(args)?,
                    &skipping,
                )?)
            },
        ),
        Tool::new(
            "idea_run",
            "Execução do workflow ligada à ideia: {ref, run} ou null.",
            schema(
                &[prop("idea", "string", ""), prop("workflow", "string", "")],
                &["idea", "workflow"],
                &[],
                &[],
            ),
            |ctx, args| {
                match app::idea_run(&ctx.store()?, args.req("idea")?, args.req("workflow")?)? {
                    Some((reference, run)) => run_and_ref(&reference, &run),
                    None => Ok("null".to_string()),
                }
            },
        )
        .read_only(),
        Tool::new(
            "ai_usage_record",
            "Registra o consumo de um turno de IA do app (JSON de UsageRecord).",
            schema(&[prop("record", "string", "JSON do registro")], &["record"], &[], &[]),
            |ctx, args| {
                let id = app::ai_usage_record(&ctx.store()?, &json_arg(args, "record")?)?;
                Ok(format!("Salvo: {id}"))
            },
        ),
    ]
}
