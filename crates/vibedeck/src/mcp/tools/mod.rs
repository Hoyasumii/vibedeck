//! Registro das tools expostas: cada área tem seu arquivo com `pub fn tools() -> Vec<Tool>`.
//! Nenhuma tool de teste é registrada aqui; testes montam seu próprio `Vec<Tool>`.

use super::tool::Tool;

mod ai;
mod app;
mod docs;
mod ideas;
mod onboarding;
pub mod project;
mod resources;
mod reviews;
mod rules;
mod stack;
mod workflows;

pub fn all() -> Vec<Tool> {
    let mut tools = Vec::new();
    tools.extend(project::tools());
    tools.extend(docs::tools());
    tools.extend(reviews::tools());
    tools.extend(rules::tools());
    tools.extend(ideas::tools());
    tools.extend(stack::tools());
    tools.extend(resources::tools());
    tools.extend(workflows::tools());
    tools.extend(ai::tools());
    tools.extend(onboarding::tools());
    tools
}

/// Tools que criam registros e, no modo app, aceitam `author` (`human`|`ai`, padrão `ai`).
const AUTHOR_TOOLS: [&str; 11] = [
    "add_review_item",
    "add_rule",
    "add_idea",
    "add_idea_rule",
    "add_stack",
    "add_pattern",
    "add_kit",
    "add_agent",
    "add_command",
    "add_skill",
    "add_workflow",
];

/// Catálogo do modo `--app`: o padrão, com as tools do app (que substituem as de mesmo nome) e `author`.
pub fn all_app() -> Vec<Tool> {
    let extra = app::tools();
    let mut tools = all();
    tools.retain(|t| !extra.iter().any(|e| e.name == t.name));
    tools.extend(extra);
    for tool in &mut tools {
        if AUTHOR_TOOLS.contains(&tool.name.as_str()) {
            add_author(&mut tool.input_schema);
        }
    }
    tools
}

fn add_author(schema: &mut serde_json::Value) {
    let author = serde_json::json!({
        "type": "string",
        "enum": ["human", "ai"],
        "description": "Autoria do registro criado: human ou ai (padrão ai).",
    });
    if let Some(object) = schema.as_object_mut() {
        object
            .entry("properties")
            .or_insert_with(|| serde_json::json!({}))
            .as_object_mut()
            .map(|p| p.insert("author".into(), author));
    }
}
