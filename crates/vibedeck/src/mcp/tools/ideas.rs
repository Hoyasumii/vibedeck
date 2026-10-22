//! Tools MCP — Ideias: CRUD, dependências, readiness, regras rascunho, promoção.

use std::collections::HashSet;

use serde_json::{Value, json};
use vibedeck_core::ideas::{IDEA_STATUSES, IdeaError, IdeaStatusExt, SlugAnd, group_path};
use vibedeck_core::model::{Author, Idea, IdeaStatus, Rule, RuleSeverity};

use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

const SEVERITIES: [&str; 2] = ["must", "should"];

fn idea_err(e: IdeaError) -> ToolError {
    ToolError::new(e.to_string())
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "list_ideas",
            "Ideias, sem força de regra.",
            schema(
                &[prop("status", "string", "")],
                &[],
                &[("status", &IDEA_STATUSES)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                // status desconhecido é ignorado em silêncio (como `flatMap(init(rawValue:))`)
                let status = args.str("status").and_then(IdeaStatus::parse);
                let rows: Vec<Value> = store
                    .ideas()?
                    .into_iter()
                    .filter(|r| status.is_none_or(|s| r.value.status == s))
                    .map(|r| {
                        let mut row = json!({
                            "group": group_path(&r.slug),
                            "slug": r.slug,
                            "title": r.value.title,
                            "status": r.value.status.raw(),
                            "tags": r.value.tags,
                            "rules": r.value.rules.len(),
                        });
                        if let Some(t) = &r.value.promoted_topic {
                            row["promotedTopic"] = json!(t);
                        }
                        row
                    })
                    .collect();
                json_text(&rows)
            },
        )
        .read_only(),
        Tool::new(
            "get_idea",
            "Ideia completa, com regras rascunho.",
            schema(&[prop("idea", "string", "")], &["idea"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                json_text(&store.idea_detail(args.req("idea")?)?)
            },
        )
        .read_only(),
        Tool::new(
            "add_idea",
            "author=ai; sem regras ativas.",
            schema(
                &[
                    prop("reference", "string", "Caminho completo grupo/slug."),
                    prop("title", "string", ""),
                    prop("body", "string", ""),
                    prop("tags", "array", ""),
                ],
                &["title"],
                &[],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let tags = args.list("tags").unwrap_or_default();
                let rec = store.create_idea(
                    args.req("title")?,
                    args.str("body"),
                    &tags,
                    Author::Ai,
                    args.str("reference"),
                )?;
                json_text(&SlugAnd {
                    idea: &rec.value,
                    slug: &rec.slug,
                })
            },
        ),
        Tool::new(
            "update_idea",
            "",
            schema(
                &[
                    prop("idea", "string", ""),
                    prop("title", "string", ""),
                    prop("body", "string", ""),
                    prop("status", "string", ""),
                    prop("tags", "array", ""),
                    prop("dependencies", "array", ""),
                ],
                &["idea"],
                &[("status", &IDEA_STATUSES)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let status = match args.str("status") {
                    None => None,
                    Some(s) => Some(IdeaStatus::parse(s).ok_or_else(|| {
                        ToolError::invalid_params(format!("Status inválido: {s}"))
                    })?),
                };
                let tags = args.list("tags");
                let reference = args.req("idea")?;
                // Lista completa (adiciona ou remove vínculos): o Core valida antes de gravar os outros campos.
                if let Some(deps) = args.list("dependencies") {
                    store
                        .set_idea_dependencies(reference, &deps)
                        .map_err(idea_err)?;
                }
                let rec = store
                    .update_idea(reference, |idea| {
                        if let Some(t) = args.str("title") {
                            idea.title = t.to_string();
                        }
                        if let Some(b) = args.str("body") {
                            idea.body = Some(b.to_string());
                        }
                        if let Some(s) = status {
                            idea.status = s;
                        }
                        if let Some(t) = tags {
                            idea.tags = t;
                        }
                        Ok(())
                    })
                    .map_err(idea_err)?;
                json_text(&SlugAnd {
                    idea: &rec.value,
                    slug: &rec.slug,
                })
            },
        ),
        Tool::new(
            "add_idea_rule",
            "Adiciona uma regra rascunho a uma ideia (vale após promote_idea).",
            schema(
                &[
                    prop("idea", "string", ""),
                    prop("text", "string", ""),
                    prop("details", "string", ""),
                    prop("severity", "string", ""),
                ],
                &["idea", "text"],
                &[("severity", &SEVERITIES)],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                let mut rule = Rule::new(args.req("text")?);
                rule.details = args.str("details").map(str::to_string);
                rule.severity = if args.severity()? == "should" {
                    RuleSeverity::Should
                } else {
                    RuleSeverity::Must
                };
                rule.author = Author::Ai;
                let (slug, saved) = store
                    .add_idea_rule(args.req("idea")?, rule)
                    .map_err(idea_err)?;
                json_text(&json!({
                    "idea": slug,
                    "ruleId": saved.id.to_string(),
                    "text": saved.text,
                }))
            },
        ),
        Tool::new(
            "promote_idea",
            "Ativa regras da ideia num tópico. Só faça isso quando o usuário pedir.",
            schema(&[prop("idea", "string", "")], &["idea"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = args.req("idea")?;
                let stale = store.unmatched_idea_paths(reference)?;
                let topic = store
                    .promote_idea(reference, &HashSet::new())
                    .map_err(idea_err)?;
                let mut text = format!("Ideia promovida para o tópico de regras: {topic}");
                if !stale.is_empty() {
                    text.push_str(&format!(
                        "\nAviso: globs da ideia que não casam nenhum arquivo foram copiados: {}",
                        stale.join(", ")
                    ));
                }
                Ok(text)
            },
        ),
        Tool::new(
            "unpromote_idea",
            "Desfaz promoção: apaga tópico, regras voltam a rascunho. Só faça isso quando o usuário pedir.",
            schema(&[prop("idea", "string", "")], &["idea"], &[], &[]),
            |ctx, args| {
                let store = ctx.store()?;
                let reference = args.req("idea")?;
                let slug = store.resolve::<Idea>(reference)?;
                if store.load::<Idea>(&slug)?.promoted_topic.is_none() {
                    return Ok("A ideia não estava promovida.".to_string());
                }
                Ok(match store.unpromote_idea(reference).map_err(idea_err)? {
                    Some(t) => format!("Ideia despromovida; tópico removido: {t}"),
                    None => "Ideia despromovida (o tópico já não existia).".to_string(),
                })
            },
        ),
    ]
}
