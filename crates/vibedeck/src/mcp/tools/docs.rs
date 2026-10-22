//! Tools MCP — Docs, grupos de itens (groups), anexos e Docs vinculados por symlink (MUD-002).
//!
//! `list_docs` acrescenta, só para docs vinculados, os campos opcionais `linked` (true), `target` e (se a
//! origem sumiu) `broken`.

use serde_json::Value;
use vibedeck_core::docs::error::DocError;
use vibedeck_core::docs::groups::{self as grp, ItemConcept};
use vibedeck_core::docs::{self, DocInfo};
use vibedeck_core::model::Author;

use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

impl From<DocError> for ToolError {
    fn from(e: DocError) -> Self {
        ToolError(e.to_string())
    }
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "item_groups",
            "Diretórios de itens. delete exige confirmed=true se não vazio, inclusive autoria humana; só a pedido do usuário.",
            schema(
                &[
                    prop("concept", "string", ""),
                    prop("action", "string", ""),
                    prop("path", "string", "Grupo."),
                    prop("from", "string", "Origem."),
                    prop("to", "string", "Destino; vazio = raiz para move_item."),
                    prop("reference", "string", "Item para move_item."),
                    prop("confirmed", "boolean", "Confirma apagar conteúdo."),
                ],
                &["concept", "action"],
                &[
                    ("concept", &ItemConcept::NAMES),
                    (
                        "action",
                        &["list", "create", "move", "rename", "move_item", "delete"],
                    ),
                ],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let concept: ItemConcept = args
                    .req("concept")?
                    .parse()
                    .map_err(|_| ToolError::invalid_params("Conceito inválido."))?;
                match args.req("action")? {
                    "list" => json_text(&grp::list_item_directories(&store, concept)?),
                    "create" => Ok(grp::create_item_directory(
                        &store,
                        concept,
                        args.req("path")?,
                    )?),
                    "move" | "rename" => {
                        grp::move_item_directory(
                            &store,
                            concept,
                            args.req("from")?,
                            args.req("to")?,
                        )?;
                        Ok("Grupo movido.".into())
                    }
                    "move_item" => {
                        // "/" é a raiz (no modo app, onde `to` vazio conta como ausente).
                        let to = match args.raw("to").and_then(Value::as_str) {
                            Some("/") => "",
                            _ => args.req("to")?,
                        };
                        Ok(grp::move_grouped_item(
                            &store,
                            concept,
                            args.req("reference")?,
                            to,
                        )?)
                    }
                    "delete" => {
                        grp::delete_item_directory(
                            &store,
                            concept,
                            args.req("path")?,
                            args.bool("confirmed") == Some(true),
                        )?;
                        Ok("Grupo apagado.".into())
                    }
                    _ => Err(ToolError::invalid_params("Operação de grupo inválida.")),
                }
            },
        ),
        Tool::new(
            "move_rule_to_group",
            "",
            schema(
                &[
                    prop("rule", "string", "ID da regra."),
                    prop("group", "string", "Grupo, vazio para raiz."),
                ],
                &["rule", "group"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let rule = grp::move_rule_to_group(&store, args.req("rule")?, args.req("group")?)?;
                json_text(&rule)
            },
        ),
        Tool::new(
            "rename_rule_group",
            "",
            schema(
                &[
                    prop("topic", "string", "Tópico."),
                    prop("from", "string", "Origem."),
                    prop("to", "string", "Destino."),
                ],
                &["topic", "from", "to"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                grp::rename_rule_group(
                    &store,
                    args.req("topic")?,
                    args.req("from")?,
                    args.req("to")?,
                )?;
                Ok("Grupo de regras movido.".into())
            },
        ),
        Tool::new("list_docs", "", schema(&[], &[], &[], &[]), |ctx, _| {
            let store = ctx.store()?;
            let rows: Vec<Value> = docs::list_docs(&store)?
                .iter()
                .map(DocInfo::to_row_json)
                .collect();
            json_text(&rows)
        })
        .read_only(),
        Tool::new(
            "read_doc",
            "",
            schema(&[prop("slug", "string", "")], &["slug"], &[], &[]),
            |ctx, args| Ok(docs::read_doc(&ctx.store()?, args.req("slug")?)?),
        )
        .read_only(),
        Tool::new(
            "write_doc",
            "generated: novo doc author=ai; senão cria/sobrescreve.",
            schema(
                &[
                    prop("reference", "string", "Caminho completo grupo/slug."),
                    prop("slug", "string", ""),
                    prop("title", "string", ""),
                    prop("content", "string", ""),
                    prop("generated", "boolean", ""),
                ],
                &["content"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let content = args.req("content")?;
                if args.bool("generated") == Some(true) {
                    let slug = docs::create_doc(
                        &store,
                        args.req("title")?,
                        content,
                        Author::Ai,
                        args.str("reference"),
                    )?;
                    return Ok(format!("Criado: {slug}"));
                }
                if let Some(slug) = args.str("slug") {
                    docs::write_doc(&store, slug, content)?;
                    return Ok(format!("Salvo: {slug}"));
                }
                let slug = docs::create_doc(
                    &store,
                    args.req("title")?,
                    "",
                    Author::Human,
                    args.str("reference"),
                )?;
                docs::write_doc(&store, &slug, content)?;
                Ok(format!("Criado: {slug}"))
            },
        ),
    ]
}
