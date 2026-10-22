//! Tools MCP — Projeto: init, status, links, coleção Claude (claude items), tags, grafo (export), logs.

use std::path::Path;

use serde_json::{Value, json};
use vibedeck_core::project::{self, ProjectError, claude, graph, links, logs, tags};

use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

fn err(e: ProjectError) -> ToolError {
    ToolError(e.to_string())
}

const KINDS: &[&str] = &["artifact", "doc"];
const INVALID_KIND: &str = "Tipo inválido: use artifact ou doc.";

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new("get_project", "", schema(&[], &[], &[], &[]), |ctx, _| {
            json_text(&project::status::overview(&ctx.store()?).map_err(err)?)
        })
        .read_only(),
        Tool::new(
            "add_link",
            "",
            schema(
                &[
                    prop("url", "string", ""),
                    prop("title", "string", ""),
                    prop("tags", "string", "Separadas por vírgula"),
                ],
                &["url"],
                &[],
                &[],
            ),
            |ctx, args| {
                let url = args.req("url")?;
                let tags = args.list("tags").unwrap_or_default();
                let link = links::add(&ctx.store()?, url, args.str("title"), tags).map_err(err)?;
                json_text(&link)
            },
        ),
        Tool::new(
            "list_claude_items",
            "Coleção curada local.",
            schema(&[prop("kind", "string", "")], &[], &[("kind", KINDS)], &[]),
            |ctx, args| {
                let kind = match args.str("kind") {
                    Some(v) => Some(
                        claude::parse_kind(v)
                            .ok_or_else(|| ToolError::invalid_params(INVALID_KIND))?,
                    ),
                    None => None,
                };
                json_text(&claude::list(&ctx.store()?, kind).map_err(err)?)
            },
        )
        .read_only(),
        Tool::new(
            "add_claude_item",
            "Só claude.ai, a pedido do usuário; ele escolhe o tipo.",
            schema(
                &[
                    prop("url", "string", ""),
                    prop("kind", "string", ""),
                    prop("title", "string", ""),
                    prop("tags", "array", ""),
                ],
                &["url", "kind"],
                &[("kind", KINDS)],
                &[],
            ),
            |ctx, args| {
                let kind = claude::parse_kind(args.req("kind")?)
                    .ok_or_else(|| ToolError::invalid_params(INVALID_KIND))?;
                let item = claude::add(
                    &ctx.store()?,
                    args.req("url")?,
                    kind,
                    args.str("title"),
                    args.list("tags").unwrap_or_default(),
                )
                .map_err(err)?;
                json_text(&item)
            },
        ),
        Tool::new(
            "export_graph",
            "Exporta graph.html offline, sem IA.",
            schema(&[], &[], &[], &[]),
            |ctx, _| {
                graph::export(ctx.store()?.root())
                    .map(str::to_string)
                    .map_err(err)
            },
        ),
        Tool::new(
            "read_logs",
            "Logs sem conteúdo; filtros por nível/período/componente/ação.",
            schema(
                &[
                    prop("level", "string", "Nível mínimo (padrão info)"),
                    prop("since", "string", "24h, 5m, 7d"),
                    prop(
                        "components",
                        "array",
                        "app, cli, mcp, core, rules, ai, hook",
                    ),
                    prop("action", "string", "Id de correlação"),
                    prop("limit", "integer", "Máximo de entradas"),
                ],
                &[],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let entries = logs::read_logs(
                    &logs::LogStore::default_store(),
                    store.root(),
                    args.str("since"),
                    args.str("level"),
                    &args.list("components").unwrap_or_default(),
                    args.str("action"),
                    args.int("limit"),
                )
                .map_err(err)?;
                json_text(&entries)
            },
        )
        .read_only(),
        Tool::new(
            "set_tags",
            "Substitui as tags de um registro (lista vazia remove).",
            schema(
                &[
                    prop("kind", "string", ""),
                    prop("ref", "string", ""),
                    prop("tags", "array", ""),
                ],
                &["kind", "ref", "tags"],
                &[(
                    "kind",
                    &[
                        "doc",
                        "review_group",
                        "rule_topic",
                        "idea",
                        "agent",
                        "command",
                        "skill",
                        "workflow",
                        "stack",
                        "pattern",
                    ],
                )],
                &[],
            ),
            |ctx, args| {
                let list = args.list("tags").unwrap_or_default();
                let reference = args.req("ref")?;
                let kind_text = args.req("kind")?;
                let kind = tags::TagKind::from_mcp(kind_text).ok_or_else(|| {
                    ToolError::invalid_params(ProjectError::InvalidTagKind(kind_text.into()))
                })?;
                tags::set_tags(&ctx.store()?, kind, reference, &list).map_err(err)?;
                Ok(tags::message(&list))
            },
        ),
    ]
}

// ---- recursos MCP desta área ------------------------------------------------------------------------

/// Itens de `resources/list` desta área, na ordem do Swift: `vibedeck://project` e os de logs.
/// INTEGRAÇÃO: o `ResourceProvider` intercala estes com stack/patterns/docs/etc. (ver mcp.md §5).
pub fn resources() -> Vec<Value> {
    vec![
        json!({"name": "vibedeck.json", "uri": "vibedeck://project",
               "description": "Manifesto do projeto", "mimeType": "application/json"}),
        json!({"name": "Logs", "uri": "vibedeck://logs",
               "description": "Erros e falhas do VibeDeck neste projeto (24h, aviso ou pior)",
               "mimeType": "application/json"}),
        json!({"name": "Crashes", "uri": "vibedeck://logs/crashes",
               "description": "Crashes do app nos últimos 14 dias", "mimeType": "application/json"}),
    ]
}

/// `resources/read` de `vibedeck://project`, `vibedeck://logs` e `vibedeck://logs/crashes`.
/// `None` = URI não é desta área. Logs usam JSON compacto; project devolve o arquivo cru.
pub fn read_resource(root: &Path, uri: &str) -> Option<Result<Value, String>> {
    let text: Result<String, String> = match uri {
        "vibedeck://project" => {
            let path = root.join("vibedeck.json");
            std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))
        }
        "vibedeck://logs" => logs::resource_logs(&logs::LogStore::default_store(), root)
            .map(|e| compact(&e))
            .map_err(|e| e.to_string()),
        "vibedeck://logs/crashes" => logs::resource_crashes(&logs::LogStore::default_store())
            .map(|e| compact(&e))
            .map_err(|e| e.to_string()),
        _ => return None,
    };
    Some(text.map(|t| json!({"uri": uri, "mimeType": "application/json", "text": t})))
}

fn compact(entries: &[logs::LogEntry]) -> String {
    let value = Value::Array(entries.iter().map(logs::LogEntry::to_json).collect());
    vibedeck_core::json::to_compact(&value)
}
