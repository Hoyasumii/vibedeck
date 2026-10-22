//! Tools MCP — IA: guia/AGENTS.md embutido, catálogo, contexto, uso, providers claude/codex, reorganize, item AI.

use serde_json::json;
use vibedeck_core::ai::codex;
use vibedeck_core::ai::context::ContextStore;
use vibedeck_core::ai::usage::{self, UsageStore};
use vibedeck_core::ai::{catalog, guide, item, reorganize};
use vibedeck_core::model::ProviderSettings;

use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

fn ai_err(e: impl std::fmt::Display) -> ToolError {
    ToolError::new(e.to_string())
}

fn kind_arg(args: &crate::mcp::args::Args) -> Result<item::Kind, ToolError> {
    item::Kind::parse(args.req("kind")?)
        .ok_or_else(|| ToolError::invalid_params(item::INVALID_KIND))
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new("codex_usage", "", schema(&[], &[], &[], &[]), |ctx, _| {
            json_text(&codex::limits(&ctx.root).map_err(ai_err)?)
        })
        .read_only(),
        Tool::new(
            "claude_usage",
            "Limites Claude pela statusline.",
            schema(&[], &[], &[], &[]),
            |_, _| {
                match usage::load_usage(&usage::usage_path()) {
                    Some(found) => json_text(&found),
                    None => Ok("Nenhum uso registrado. O usuário precisa ligar a statusline com `vibedeck usage install`.".to_string()),
                }
            },
        )
        .read_only(),
        Tool::new(
            "ai_guide",
            "",
            schema(&[prop("section", "integer", "Omita para o índice")], &[], &[], &[]),
            |_, args| {
                if let Some(n) = args.int_strict("section") {
                    return guide::section(n)
                        .ok_or_else(|| ToolError::invalid_params("Seção inexistente."));
                }
                Ok(guide::index())
            },
        )
        .read_only(),
        Tool::new(
            "ai_catalog",
            "Índice sem prompts; inclui kits.",
            schema(
                &[
                    prop("kind", "string", "agents, commands, skills, workflows, rules, kits"),
                    prop("offset", "integer", ""),
                    prop("limit", "integer", "1 a 100, padrão 20"),
                ],
                &["kind"],
                &[],
                &[],
            ),
            |ctx, args| {
                let kind = args.req("kind")?;
                if kind == "kits" {
                    let offset = args.int_strict("offset").unwrap_or(0).max(0) as usize;
                    let limit = args.int_strict("limit").unwrap_or(20).clamp(1, 100) as usize;
                    let page: Vec<_> = vibedeck_core::resources::kits::kits()
                        .iter()
                        .skip(offset)
                        .take(limit)
                        .collect();
                    return json_text(&page);
                }
                let store = ctx.store()?;
                let page = catalog::catalog(
                    &store,
                    kind,
                    args.int_strict("offset").unwrap_or(0),
                    args.int_strict("limit").unwrap_or(20),
                )
                .map_err(ai_err)?;
                json_text(&page)
            },
        )
        .read_only(),
        Tool::new(
            "ai_context",
            "Página; nextOffset continua.",
            schema(
                &[
                    prop("id", "string", ""),
                    prop("offset", "integer", ""),
                    prop("limit", "integer", "1 a 16000, padrão 4000"),
                ],
                &["id"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let page = ContextStore::for_root(store.root())
                    .page(
                        args.req("id")?,
                        args.int_strict("offset").unwrap_or(0),
                        args.int_strict("limit").unwrap_or(4000),
                    )
                    .map_err(ai_err)?;
                json_text(&page)
            },
        )
        .read_only(),
        Tool::new(
            "reorganize_prompt",
            "Prompt/schema/hash.",
            schema(&[], &[], &[], &[]),
            |ctx, _| {
                let store = ctx.store()?;
                json_text(&json!({
                    "prompt": reorganize::prompt(&store).map_err(ai_err)?,
                    "schema": reorganize::SCHEMA,
                    "fingerprint": reorganize::fingerprint(&store).map_err(ai_err)?,
                }))
            },
        )
        .read_only(),
        Tool::new(
            "reorganize_analyze",
            "Somente leitura.",
            schema(
                &[
                    prop("provider", "string", "claude ou codex"),
                    prop("model", "string", ""),
                    prop("effort", "string", ""),
                ],
                &["provider"],
                &[],
                &[],
            ),
            |ctx, args| {
                args.req("provider")?;
                let provider = match args.provider()? {
                    "codex" => vibedeck_core::ai::Provider::Codex,
                    _ => vibedeck_core::ai::Provider::Claude,
                };
                let store = ctx.store()?;
                let settings = ProviderSettings {
                    model: args.str("model").map(str::to_string),
                    effort: args.str("effort").map(str::to_string),
                };
                json_text(&reorganize::analyze(&store, provider, &settings).map_err(ai_err)?)
            },
        )
        .read_only(),
        Tool::new(
            "reorganize_validate",
            "Valida sem gravar.",
            schema(
                &[
                    prop("answer", "string", "JSON"),
                    prop("fingerprint", "string", "Do reorganize_prompt"),
                ],
                &["answer", "fingerprint"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let answer = args.req("answer")?;
                let proposal =
                    reorganize::parse(answer.as_bytes(), &store, args.req("fingerprint")?)
                        .map_err(ai_err)?;
                json_text(&proposal)
            },
        )
        .read_only(),
        Tool::new(
            "reorganize_apply",
            "Só com aceite; conflicts exige escolha explícita.",
            schema(
                &[
                    prop("proposal", "string", "JSON validado"),
                    prop("acceptance", "string", "JSON: selected e conflicts"),
                ],
                &["proposal", "acceptance"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let proposal =
                    reorganize::decode_proposal(args.req("proposal")?.as_bytes()).map_err(ai_err)?;
                let acceptance =
                    reorganize::decode_acceptance(args.req("acceptance")?.as_bytes())
                        .map_err(ai_err)?;
                json_text(&reorganize::apply(&store, &proposal, &acceptance).map_err(ai_err)?)
            },
        ),
        Tool::new(
            "item_ai_prompt",
            "Prompt+schema para criar/editar agent, command, skill ou workflow com IA (não grava).",
            schema(
                &[
                    prop("kind", "string", "agent|command|skill|workflow"),
                    prop("request", "string", ""),
                    prop("item", "string", "Editar; omita para criar"),
                ],
                &["kind", "request"],
                &[],
                &[],
            ),
            |ctx, args| {
                let kind = kind_arg(args)?;
                let store = ctx.store()?;
                let (prompt, schema) =
                    item::item_ai_prompt(&store, kind, args.req("request")?, args.str("item"))
                        .map_err(ai_err)?;
                json_text(&json!({"prompt": prompt, "schema": schema}))
            },
        )
        .read_only(),
        Tool::new(
            "item_ai_apply",
            "Valida o JSON do schema e cria (author=ai) ou, com item, substitui.",
            schema(
                &[
                    prop("kind", "string", "agent|command|skill|workflow"),
                    prop("proposal", "string", "JSON"),
                    prop("item", "string", "Substituir; omita para criar"),
                ],
                &["kind", "proposal"],
                &[],
                &[],
            ),
            |ctx, args| {
                let kind = kind_arg(args)?;
                let store = ctx.store()?;
                let slug = item::item_ai_apply(
                    &store,
                    kind,
                    args.req("proposal")?.as_bytes(),
                    args.str("item"),
                )
                .map_err(ai_err)?;
                Ok(format!("Gravado: {slug}"))
            },
        ),
        Tool::new(
            "ai_usage",
            "Consumo por tarefa; ausentes não são zero. clear só a pedido do usuário.",
            schema(&[prop("clear", "boolean", "")], &[], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let usage_store = UsageStore::for_root(store.root());
                if args.bool("clear") == Some(true) {
                    usage_store.clear().map_err(ai_err)?;
                    return Ok("Métricas locais apagadas.".to_string());
                }
                json_text(&usage_store.list().map_err(ai_err)?)
            },
        ),
    ]
}
