//! Tools MCP — Revisões: grupos e itens de revisão (mcp.md §4.3).

use crate::mcp::args::Args;
use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text};
use vibedeck_core::model::{Author, ReviewPriority, ReviewTarget};
use vibedeck_core::reviews::{self, ItemUpdate, NewItem, PRIORITIES, ReviewError, STATUSES};

fn review_err(e: ReviewError) -> ToolError {
    if e.is_invalid_params() {
        ToolError::invalid_params(e)
    } else {
        ToolError::new(e.to_string())
    }
}

fn list_review_groups(ctx: &ToolCtx, _args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    json_text(&reviews::group_rows(&store)?)
}

fn list_review_items(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    // Status desconhecido não filtra (como o `flatMap(ReviewStatus.init)` do Swift).
    let status = args.str("status").and_then(reviews::parse_status);
    let rows = reviews::list_items(&store, args.str("group"), status, args.str("kind"))?;
    json_text(&rows)
}

fn add_review_item(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let kind = args.req("kind")?.to_string();
    let title = args.req("title")?.to_string();
    let group = args.req("group")?.to_string();
    let new = NewItem {
        kind,
        title,
        details: args.str("details").map(str::to_string),
        priority: args
            .str("priority")
            .and_then(reviews::parse_priority)
            .unwrap_or(ReviewPriority::Normal),
        target: ReviewTarget {
            file: args.str("file").map(str::to_string),
            route: args.str("route").map(str::to_string),
            component: args.str("component").map(str::to_string),
            selector: args.str("selector").map(str::to_string),
        },
        rules: args.list("rules").unwrap_or_default(),
        author: Author::Ai,
    };
    let (slug, item) = reviews::add_item(&store, new, &group).map_err(review_err)?;
    json_text(&reviews::ItemRow { group: slug, item })
}

fn update_review_item(ctx: &ToolCtx, args: &Args) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let id = args.req("id")?;
    let change = ItemUpdate {
        rules: args.list("rules"),
        status: args.str("status").map(str::to_string),
        priority: args.str("priority").and_then(reviews::parse_priority),
        kind: args.str("kind").map(str::to_string),
        title: args.str("title").map(str::to_string),
        details: args.str("details").map(str::to_string),
        force: false,
    };
    let item = reviews::apply_update(&store, id, change).map_err(review_err)?;
    json_text(&item)
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "list_review_groups",
            "Grupos com itens abertos.",
            schema(&[], &[], &[], &[]),
            list_review_groups,
        )
        .read_only(),
        Tool::new(
            "list_review_items",
            "",
            schema(
                &[
                    prop("group", "string", ""),
                    prop("status", "string", ""),
                    prop("kind", "string", "Ver reviewKinds"),
                ],
                &[],
                &[("status", &STATUSES)],
                &[],
            ),
            list_review_items,
        )
        .read_only(),
        Tool::new(
            "add_review_item",
            "author=ai; grupo automático.",
            schema(
                &[
                    prop("group", "string", ""),
                    prop("kind", "string", "Ver reviewKinds"),
                    prop("title", "string", ""),
                    prop("details", "string", ""),
                    prop("priority", "string", ""),
                    prop("file", "string", ""),
                    prop("route", "string", ""),
                    prop("component", "string", ""),
                    prop("selector", "string", ""),
                    prop("rules", "array", "Tópicos de regras do item"),
                ],
                &["group", "kind", "title"],
                &[("priority", &PRIORITIES)],
                &[],
            ),
            add_review_item,
        ),
        Tool::new(
            "update_review_item",
            "Atualiza item; com regras, done exige check aprovado para review_item.",
            schema(
                &[
                    prop("id", "string", ""),
                    prop("status", "string", ""),
                    prop("priority", "string", ""),
                    prop("title", "string", ""),
                    prop("details", "string", ""),
                    prop("kind", "string", ""),
                    prop("rules", "array", "Substitui os tópicos"),
                ],
                &["id"],
                &[("status", &STATUSES), ("priority", &PRIORITIES)],
                &[],
            ),
            update_review_item,
        ),
    ]
}
