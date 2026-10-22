//! Tools MCP — Stack e padrões (catálogo, ícones Skill Icons, badge).

use std::collections::HashSet;

use serde_json::{Value, json};
use vibedeck_core::model::Author;
use vibedeck_core::stack::icons::CATEGORIES;
use vibedeck_core::stack::{PatternCatalog, SkillIcons, SkillIconsApi, StackError, StackService};

use crate::mcp::args::Args;
use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text};

impl From<StackError> for ToolError {
    fn from(e: StackError) -> Self {
        ToolError(e.to_string())
    }
}

fn param_required(name: &str) -> ToolError {
    ToolError::invalid_params(format!("Parâmetro obrigatório: {name}"))
}

/// `PatternListing`: padrões do projeto com escopo e regras dos seus tópicos.
fn pattern_listing(ctx: &ToolCtx) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let rows = store
        .project()?
        .patterns
        .iter()
        .map(|p| {
            let topic = store.pattern_topic(p);
            let mut row = serde_json::to_value(p).unwrap_or(Value::Null);
            let obj = row.as_object_mut().expect("padrão é objeto");
            // Só as chaves do `CodingKeys` do Swift.
            obj.retain(|k, _| {
                matches!(
                    k.as_str(),
                    "id" | "name" | "category" | "summary" | "note" | "author"
                )
            });
            if let Some(t) = &topic {
                obj.insert("topic".into(), json!(t.slug));
            }
            let (paths, rules) = match &topic {
                Some(t) => (
                    serde_json::to_value(&t.value.paths).unwrap_or(json!([])),
                    serde_json::to_value(&t.value.rules).unwrap_or(json!([])),
                ),
                None => (json!([]), json!([])),
            };
            obj.insert("paths".into(), paths);
            obj.insert("rules".into(), rules);
            row
        })
        .collect::<Vec<_>>();
    json_text(&json!({ "patterns": rows }))
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new("list_stack", "", schema(&[], &[], &[], &[]), |ctx, _| {
            let store = ctx.store()?;
            let stack = store.project()?.stack;
            let badge = if stack.is_empty() {
                None
            } else {
                let api = SkillIcons::default();
                StackService::new(&store, &api)
                    .badge(None)
                    .ok()
                    .flatten()
                    .map(|b| b.url)
            };
            json_text(&json!({ "stack": stack, "badge": badge }))
        })
        .read_only(),
        Tool::new(
            "search_stack_icons",
            "IDs para add_stack.",
            schema(
                &[
                    prop("query", "string", "Vazio = tudo"),
                    prop("category", "string", ""),
                    prop("limit", "integer", "Padrão 50"),
                ],
                &[],
                &[("category", &CATEGORIES)],
                &[],
            ),
            |ctx, args| {
                let api = SkillIcons::default();
                let icons = api
                    .search(args.str("query"), args.str("category"), args.int("limit"))
                    .map_err(ToolError::from)?;
                let current: HashSet<String> = ctx
                    .store()?
                    .project()?
                    .stack
                    .into_iter()
                    .map(|i| i.icon)
                    .collect();
                let rows = icons
                    .iter()
                    .map(|i| {
                        let mut row = json!({
                            "id": i.id, "name": i.name, "themed": i.themed,
                            "inStack": current.contains(&i.id),
                        });
                        if let Some(c) = &i.category {
                            row["category"] = json!(c);
                        }
                        if !i.aliases.is_empty() {
                            row["aliases"] = json!(i.aliases);
                        }
                        row
                    })
                    .collect::<Vec<_>>();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "add_stack",
            "Atualiza badge; desconhecidas recusam tudo.",
            schema(
                &[
                    prop("icons", "array", "Ids, nomes ou aliases, na ordem"),
                    prop("note", "string", "Nota de uso para todas"),
                ],
                &["icons"],
                &[],
                &[],
            ),
            |ctx, args| {
                let icons = args
                    .list("icons")
                    .filter(|l| !l.is_empty())
                    .ok_or_else(|| param_required("icons"))?;
                let store = ctx.store()?;
                let api = SkillIcons::default();
                let change = StackService::new(&store, &api).add(
                    &icons,
                    args.raw("note").and_then(Value::as_str),
                    Author::Ai,
                )?;
                json_text(&change)
            },
        ),
        Tool::new(
            "remove_stack",
            "Atualiza badge.",
            schema(&[prop("icons", "array", "")], &["icons"], &[], &[]),
            |ctx, args| {
                let icons = args
                    .list("icons")
                    .filter(|l| !l.is_empty())
                    .ok_or_else(|| param_required("icons"))?;
                let store = ctx.store()?;
                let api = SkillIcons::default();
                json_text(&StackService::new(&store, &api).remove(&icons)?)
            },
        ),
        Tool::new(
            "update_stack",
            "",
            schema(
                &[
                    prop("icon", "string", ""),
                    prop("note", "string", "Vazia apaga"),
                    prop("position", "integer", "A partir de 0"),
                ],
                &["icon"],
                &[],
                &[],
            ),
            |ctx, args| {
                let icon = args.req("icon")?;
                let store = ctx.store()?;
                let api = SkillIcons::default();
                let service = StackService::new(&store, &api);
                let mut change = None;
                if let Some(note) = args.raw("note").and_then(Value::as_str) {
                    change = Some(service.set_note(icon, Some(note))?);
                }
                if let Some(position) = args.int("position") {
                    change = Some(service.move_to(icon, position)?);
                }
                let change =
                    change.ok_or_else(|| ToolError::invalid_params("Informe note ou position."))?;
                json_text(&change)
            },
        ),
        Tool::new("list_patterns", "", schema(&[], &[], &[], &[]), |ctx, _| {
            pattern_listing(ctx)
        })
        .read_only(),
        Tool::new(
            "pattern_catalog",
            "Catálogo para add_pattern.",
            schema(&[prop("query", "string", "Vazio = tudo")], &[], &[], &[]),
            |ctx, args| {
                let current: HashSet<String> = ctx
                    .store()?
                    .project()?
                    .patterns
                    .into_iter()
                    .map(|p| p.id)
                    .collect();
                let rows = PatternCatalog::search(args.str("query"))
                    .into_iter()
                    .map(|t| {
                        let mut row = json!({
                            "id": t.id, "name": t.name, "category": t.category,
                            "summary": t.summary,
                            "rules": t.rules.iter().map(|r| &r.text).collect::<Vec<_>>(),
                            "inProject": current.contains(&t.id),
                        });
                        if !t.aliases.is_empty() {
                            row["aliases"] = json!(t.aliases);
                        }
                        row
                    })
                    .collect::<Vec<_>>();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "add_pattern",
            "Padrões: catálogo (patterns) ou personalizado (name+rules); cada um cria tópico.",
            schema(
                &[
                    prop("patterns", "array", "Ids do catálogo"),
                    prop("name", "string", ""),
                    prop("summary", "string", ""),
                    prop("rules", "array", "Regras do personalizado"),
                    prop("note", "string", "Como o projeto aplica"),
                    prop("paths", "array", "Globs; vazio = projeto inteiro"),
                ],
                &[],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let paths = args.list("paths");
                if let Some(name) = args.str("name") {
                    let rules = args
                        .list("rules")
                        .filter(|l| !l.is_empty())
                        .ok_or_else(|| {
                            ToolError::invalid_params("Padrão personalizado precisa de rules.")
                        })?;
                    store.add_custom_pattern(
                        name,
                        args.str("summary"),
                        &rules,
                        args.str("note"),
                        paths.as_deref(),
                        Author::Ai,
                    )?;
                } else {
                    let refs =
                        args.list("patterns")
                            .filter(|l| !l.is_empty())
                            .ok_or_else(|| {
                                ToolError::invalid_params(
                                    "Informe patterns (catálogo) ou name + rules.",
                                )
                            })?;
                    store.add_patterns(&refs, args.str("note"), paths.as_deref(), Author::Ai)?;
                }
                pattern_listing(ctx)
            },
        ),
        Tool::new(
            "remove_pattern",
            "Retira padrões e apaga seus tópicos de regras.",
            schema(&[prop("patterns", "array", "")], &["patterns"], &[], &[]),
            |ctx, args| {
                let refs = args
                    .list("patterns")
                    .filter(|l| !l.is_empty())
                    .ok_or_else(|| param_required("patterns"))?;
                ctx.store()?.remove_patterns(&refs)?;
                pattern_listing(ctx)
            },
        ),
        Tool::new(
            "update_pattern",
            "",
            schema(
                &[
                    prop("pattern", "string", ""),
                    prop("note", "string", "Vazia apaga"),
                    prop("paths", "array", "[] = projeto inteiro"),
                    prop("position", "integer", "A partir de 0"),
                ],
                &["pattern"],
                &[],
                &[],
            ),
            |ctx, args| {
                let reference = args.req("pattern")?;
                if args.raw("note").is_none()
                    && args.raw("paths").is_none()
                    && args.int("position").is_none()
                {
                    return Err(ToolError::invalid_params(
                        "Informe note, paths ou position.",
                    ));
                }
                let store = ctx.store()?;
                if let Some(note) = args.raw("note").and_then(Value::as_str) {
                    store.set_pattern_note(reference, Some(note))?;
                }
                if args.raw("paths").is_some() {
                    store.set_pattern_paths(reference, &args.list("paths").unwrap_or_default())?;
                }
                if let Some(position) = args.int("position") {
                    store.move_pattern(reference, position)?;
                }
                pattern_listing(ctx)
            },
        ),
    ]
}
