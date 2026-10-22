//! Tools MCP — Agentes, comandos, skills, kits e importação (`list/get/add/update`, próximos passos,
//! fluxos, `import_*` e `add_kit`). Mesma lógica do CLI: tudo vem de `vibedeck_core::resources`.

use serde_json::{Value, json};
use vibedeck_core::Store;
use vibedeck_core::model::{
    Agent, AiProvider, Author, Command, NextStepKind, ProviderSettingsMap, Skill,
};
use vibedeck_core::resources::{self, NewPersona, Persona, ResourceError};

use crate::mcp::args::Args;
use crate::mcp::schema::{Prop, prop, schema};
use crate::mcp::tool::{Tool, ToolCtx, ToolError, json_text};

type Importer = fn(
    &Store,
    AiProvider,
    Option<&[std::path::PathBuf]>,
    bool,
    Author,
) -> resources::Result<resources::ImportResult>;

const STEP_KINDS: &[&str] = &["agent", "command", "skill"];
const PROVIDER_SETTINGS: &str = "{codex|claude:{model,effort}}";
const PROVIDER: &str = "claude (padrão)|codex";

fn err(e: ResourceError) -> ToolError {
    ToolError::new(e.to_string())
}

fn provider_settings(a: &Args) -> Result<Option<ProviderSettingsMap>, ToolError> {
    let Some(value) = a.raw("provider_settings") else {
        return Ok(None);
    };
    let parsed: ProviderSettingsMap =
        serde_json::from_value(value.clone()).map_err(|e| ToolError::new(e.to_string()))?;
    if parsed.keys().any(|k| k != "claude" && k != "codex") {
        return Err(ToolError::invalid_params(
            "Provedor inválido em provider_settings",
        ));
    }
    Ok(Some(parsed))
}

fn step_kind(a: &Args) -> Result<NextStepKind, ToolError> {
    match a.str("kind") {
        None | Some("agent") => Ok(NextStepKind::Agent),
        Some("command") => Ok(NextStepKind::Command),
        Some("skill") => Ok(NextStepKind::Skill),
        Some(k) => Err(ToolError::invalid_params(format!("Tipo inválido: {k}"))),
    }
}

fn slug_json<P: Persona>(slug: &str, value: &P) -> Result<String, ToolError> {
    let v = resources::with_slug(slug, value);
    json_text(&v)
}

fn list_rows<P: Persona>(store: &Store) -> Result<String, ToolError> {
    let rows: Vec<Value> = store
        .list::<P>()
        .map_err(ToolError::from)?
        .iter()
        .map(|r| resources::mcp_row(&r.slug, &r.value))
        .collect();
    json_text(&rows)
}

fn get<P: Persona>(ctx: &ToolCtx, a: &Args, key: &str) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let slug = store.resolve::<P>(a.req(key)?).map_err(ToolError::from)?;
    let value = store.load::<P>(&slug).map_err(ToolError::from)?;
    slug_json(&slug, &value)
}

fn add<P: Persona>(
    ctx: &ToolCtx,
    a: &Args,
    hint: bool,
    reference: bool,
) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let new = NewPersona {
        title: a.req("title")?.to_string(),
        summary: a.str("summary").map(str::to_string),
        argument_hint: if hint {
            a.str("argument_hint").map(str::to_string)
        } else {
            None
        },
        model: a.str("model").map(str::to_string),
        tools: a.list("tools").unwrap_or_default(),
        prompt: a.str("prompt").unwrap_or("").to_string(),
        tags: a.list("tags").unwrap_or_default(),
        author: ctx.author(a)?,
        reference: if reference {
            a.str("reference").map(str::to_string)
        } else {
            None
        },
    };
    let settings = provider_settings(a)?;
    let mut rec = resources::create::<P>(&store, new).map_err(err)?;
    if let Some(settings) = settings {
        rec = resources::update::<P>(&store, &rec.slug, |f| {
            *f.provider_settings = Some(settings.clone());
            Ok(())
        })
        .map_err(err)?;
    }
    slug_json(&rec.slug, &rec.value)
}

fn update<P: Persona>(ctx: &ToolCtx, a: &Args, key: &str, hint: bool) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let reference = a.req(key)?.to_string();
    let overrides = provider_settings(a)?;
    let tags = a.list("tags");
    let tools = a.list("tools");
    let rec = resources::update::<P>(&store, &reference, |f| {
        if let Some(o) = &overrides {
            *f.provider_settings = Some(o.clone());
        }
        if let Some(t) = a.str("title") {
            *f.title = t.to_string();
        }
        if let Some(v) = a.str("summary") {
            *f.summary = Some(v.to_string());
        }
        if hint
            && let (Some(v), Some(slot)) = (a.str("argument_hint"), f.argument_hint.as_deref_mut())
        {
            *slot = Some(v.to_string());
        }
        if let Some(v) = a.str("model") {
            *f.model = Some(v.to_string());
        }
        if let Some(v) = a.str("prompt") {
            *f.prompt = v.to_string();
        }
        if let Some(t) = &tools {
            *f.tools = t.clone();
        }
        if let Some(t) = &tags {
            *f.tags = t.clone();
        }
        Ok(())
    })
    .map_err(err)?;
    slug_json(&rec.slug, &rec.value)
}

fn next_step<P: Persona>(ctx: &ToolCtx, a: &Args, key: &str) -> Result<String, ToolError> {
    let store = ctx.store()?;
    let reference = a.req(key)?;
    let kind = step_kind(a)?;
    let rec =
        resources::add_next_step::<P>(&store, reference, kind, a.req("target")?, a.str("note"))
            .map_err(err)?;
    slug_json(&rec.slug, &rec.value)
}

fn flow<P: Persona>(ctx: &ToolCtx, a: &Args, key: &str) -> Result<String, ToolError> {
    let store = ctx.store()?;
    resources::flow_for(&store, P::KIND, a.req(key)?).map_err(err)
}

fn import(ctx: &ToolCtx, a: &Args, importer: Importer) -> Result<String, ToolError> {
    let provider = a.provider()?;
    let store = ctx.store()?;
    let provider_enum = if provider == "codex" {
        AiProvider::Codex
    } else {
        AiProvider::Claude
    };
    let result = importer(
        &store,
        provider_enum,
        None,
        a.bool("overwrite").unwrap_or(false),
        Author::Ai,
    )
    .map_err(err)?;
    if provider_enum == AiProvider::Claude {
        json_text(&result.slugs)
    } else {
        json_text(&json!({"slugs": result.slugs, "warnings": result.warnings}))
    }
}

fn settings_prop() -> Prop {
    prop("provider_settings", "object", PROVIDER_SETTINGS)
}

fn persona_props(key: &'static str, extra: &[Prop], with_summary_hint: &'static str) -> Vec<Prop> {
    let mut v = vec![settings_prop(), prop(key, "string", "")];
    v.extend(extra.iter().map(|p| prop(p.name, p.ty, p.description)));
    v.push(prop("title", "string", ""));
    v.push(prop("summary", "string", with_summary_hint));
    v
}

fn common_tail() -> Vec<Prop> {
    vec![
        prop("model", "string", ""),
        prop("tools", "array", ""),
        prop("prompt", "string", ""),
        prop("tags", "array", ""),
    ]
}

fn add_schema(extra: &[Prop], summary_hint: &'static str, reference: bool) -> Value {
    let mut props = Vec::new();
    if reference {
        props.push(prop("reference", "string", "Caminho completo grupo/slug."));
    }
    props.push(settings_prop());
    props.push(prop("title", "string", ""));
    props.push(prop("summary", "string", summary_hint));
    for p in extra {
        props.push(prop(p.name, p.ty, p.description));
    }
    props.extend(common_tail());
    schema(
        &props,
        &["title"],
        &[],
        &[(
            "provider_settings",
            json!({"type": "object", "description": PROVIDER_SETTINGS}),
        )],
    )
}

fn update_schema(key: &'static str, extra: &[Prop]) -> Value {
    let mut props = persona_props(key, extra, "");
    props.extend(common_tail());
    schema(
        &props,
        &[key],
        &[],
        &[(
            "provider_settings",
            json!({"type": "object", "description": PROVIDER_SETTINGS}),
        )],
    )
}

fn step_schema(key: &'static str) -> Value {
    schema(
        &[
            prop(key, "string", ""),
            prop("target", "string", ""),
            prop("kind", "string", ""),
            prop("note", "string", ""),
        ],
        &[key, "target"],
        &[("kind", STEP_KINDS)],
        &[],
    )
}

fn key_schema(key: &'static str) -> Value {
    schema(&[prop(key, "string", "")], &[key], &[], &[])
}

fn import_schema() -> Value {
    schema(
        &[
            prop("provider", "string", PROVIDER),
            prop("overwrite", "boolean", ""),
        ],
        &[],
        &[],
        &[],
    )
}

#[allow(clippy::too_many_arguments)]
fn group<P: Persona + 'static>(
    key: &'static str,
    plural: &'static str,
    singular: &'static str,
    add_desc: &'static str,
    update_desc: &'static str,
    step_desc: &'static str,
    extra: Vec<Prop>,
    summary_hint: &'static str,
    hint: bool,
    reference: bool,
    importer: Importer,
) -> Vec<Tool> {
    vec![
        Tool::new(
            &format!("list_{plural}"),
            "",
            schema(&[], &[], &[], &[]),
            |c, _| list_rows::<P>(&c.store()?),
        )
        .read_only(),
        Tool::new(
            &format!("get_{singular}"),
            "",
            key_schema(key),
            move |c, a| get::<P>(c, a, key),
        )
        .read_only(),
        Tool::new(
            &format!("add_{singular}"),
            add_desc,
            add_schema(&extra, summary_hint, reference),
            move |c, a| add::<P>(c, a, hint, reference),
        ),
        Tool::new(
            &format!("update_{singular}"),
            update_desc,
            update_schema(key, &extra),
            move |c, a| update::<P>(c, a, key, hint),
        ),
        Tool::new(
            &format!("add_{singular}_next_step"),
            step_desc,
            step_schema(key),
            move |c, a| next_step::<P>(c, a, key),
        ),
        Tool::new(
            &format!("{singular}_flow"),
            "",
            key_schema(key),
            move |c, a| flow::<P>(c, a, key),
        )
        .read_only(),
        Tool::new(
            &format!("import_{plural}"),
            "",
            import_schema(),
            move |c, a| import(c, a, importer),
        ),
    ]
}

pub fn tools() -> Vec<Tool> {
    let mut tools = vec![Tool::new(
        "add_kit",
        "Adiciona ids de kits/itens selecionados, com dependências. author=ai.",
        schema(&[prop("items", "array", "")], &["items"], &[], &[]),
        |c, a| {
            let items = a.list("items").unwrap_or_default();
            let store = c.store()?;
            let added = resources::add_kit_items(&store, &items, c.author(a)?).map_err(err)?;
            json_text(&added)
        },
    )];
    tools.extend(group::<Agent>(
        "agent",
        "agents",
        "agent",
        "",
        "Fluxo: add_agent_next_step.",
        "Encadeia agente/comando/skill sobre o resultado do agente.",
        vec![],
        "Quando usar",
        false,
        false,
        resources::import_agents,
    ));
    tools.extend(group::<Command>(
        "command",
        "commands",
        "command",
        "Aceita $ARGUMENTS.",
        "Fluxo: add_command_next_step.",
        "Encadeia agente/comando/skill sobre o resultado do comando.",
        vec![prop("argument_hint", "string", "Conteúdo de $ARGUMENTS")],
        "",
        true,
        false,
        resources::import_commands,
    ));
    tools.extend(group::<Skill>(
        "skill",
        "skills",
        "skill",
        "Cria skill (SKILL.md); summary define quando disparar.",
        "Fluxo: add_skill_next_step.",
        "Encadeia agente/comando/skill sobre o resultado da skill.",
        vec![],
        "Quando usar",
        false,
        true,
        resources::import_skills,
    ));
    tools
}
