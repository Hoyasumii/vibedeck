//! "Descubra" em itens de revisão — parte Core, sem provider: ferramentas somente-leitura, schema, prompt,
//! leitura da saída `claude -p --output-format json`, validação em proposta e aplicação das escolhas.
//! A chamada ao `claude` (spawn, timeout de 180 s) fica na área `ai`.

use std::path::Path;

use serde::Deserialize;
use serde_json::Value;

use crate::model::*;
use crate::paths;
use crate::rules::{TopicExt, relative_to_root};
use crate::store::{Record, Store};

/// Ferramentas permitidas na chamada. Qualquer outra (Edit, Write, Bash, servidores MCP) fica indisponível.
pub const TOOLS: [&str; 3] = ["Read", "Grep", "Glob"];
/// Timeout da chamada, em segundos.
pub const TIMEOUT_SECS: u64 = 180;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DiscoverError {
    #[error("O Claude Code respondeu num formato inesperado; nada foi alterado. Tente de novo.")]
    InvalidAnswer,
    #[error("O Claude Code não conseguiu descobrir; nada foi alterado.{}", if .0.is_empty() { String::new() } else { format!("\n{}", .0) })]
    Failed(String),
    #[error("O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo.")]
    TimedOut,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Field {
    File,
    Route,
    Component,
    Selector,
}

impl Field {
    pub const ALL: [Field; 4] = [Field::File, Field::Route, Field::Component, Field::Selector];

    pub fn raw(self) -> &'static str {
        match self {
            Field::File => "file",
            Field::Route => "route",
            Field::Component => "component",
            Field::Selector => "selector",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Field::File => "Arquivo",
            Field::Route => "Rota / tela",
            Field::Component => "Componente",
            Field::Selector => "Seletor",
        }
    }

    pub fn get(self, target: &ReviewTarget) -> Option<&String> {
        match self {
            Field::File => target.file.as_ref(),
            Field::Route => target.route.as_ref(),
            Field::Component => target.component.as_ref(),
            Field::Selector => target.selector.as_ref(),
        }
    }

    pub fn set(self, target: &mut ReviewTarget, value: Option<String>) {
        match self {
            Field::File => target.file = value,
            Field::Route => target.route = value,
            Field::Component => target.component = value,
            Field::Selector => target.selector = value,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct FieldSuggestion {
    pub field: Field,
    pub value: String,
    #[serde(default)]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct TopicSuggestion {
    pub slug: String,
    #[serde(default)]
    pub reason: Option<String>,
}

/// O que o Claude responde (forçado por `--json-schema`).
#[derive(Debug, Clone, PartialEq, Eq, Default, Deserialize)]
pub struct Answer {
    #[serde(default, deserialize_with = "null_default")]
    pub fields: Vec<FieldSuggestion>,
    #[serde(default, deserialize_with = "null_default")]
    pub rules: Vec<TopicSuggestion>,
}

fn null_default<'de, D, T>(d: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de> + Default,
{
    Ok(Option::<T>::deserialize(d)?.unwrap_or_default())
}

pub const SCHEMA: &str = r#"{"type":"object","properties":{"fields":{"type":"array","items":{"type":"object","properties":{"field":{"type":"string","enum":["file","route","component","selector"]},"value":{"type":"string"},"reason":{"type":"string"}},"required":["field","value","reason"]}},"rules":{"type":"array","items":{"type":"object","properties":{"slug":{"type":"string"},"reason":{"type":"string"}},"required":["slug","reason"]}}},"required":["fields","rules"]}"#;

/// Argumentos de `claude -p` (o prompt vai no stdin). `prompt_policy` é `AIPromptPolicy.instructions`
/// (área `ai`). `--strict-mcp-config` sem config deixa de fora todo servidor MCP, inclusive o do projeto.
pub fn arguments(prompt_policy: &str) -> Vec<String> {
    let tools = TOOLS.join(",");
    [
        "-p",
        "--output-format",
        "json",
        "--json-schema",
        SCHEMA,
        "--tools",
        &tools,
        "--allowedTools",
        &tools,
        "--strict-mcp-config",
        "--no-session-persistence",
        "--append-system-prompt",
        prompt_policy,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

/// Tópicos que valem sugerir: não globais, ainda não ligados ao item e que não casam o arquivo dele.
pub fn candidate_topics<'a>(
    topics: &'a [Record<RuleTopic>],
    item: &ReviewItem,
) -> Vec<&'a Record<RuleTopic>> {
    let file = item.target.as_ref().and_then(|t| t.file.as_deref());
    topics
        .iter()
        .filter(|t| {
            !t.value.is_global()
                && !item.rules.contains(&t.slug)
                && !file.is_some_and(|f| t.value.matches_file(f))
        })
        .collect()
}

pub fn prompt(item: &ReviewItem, kind: &str, topics: &[&Record<RuleTopic>]) -> String {
    let mut lines: Vec<String> = vec![
        "Você está preenchendo um item de revisão do VibeDeck neste repositório (o diretório atual).".into(),
        "Use leitura e busca para encontrar no código onde o item se aplica. Não altere nada.".into(),
        String::new(),
        "## Item".into(),
        format!("Título: {}", item.title),
        format!("Tipo: {kind}"),
    ];
    if let Some(d) = item.details.as_deref().filter(|d| !d.is_empty()) {
        lines.push(format!("Detalhes: {d}"));
    }
    let current: Vec<String> = Field::ALL
        .iter()
        .filter_map(|f| {
            item.target
                .as_ref()
                .and_then(|t| f.get(t))
                .map(|v| format!("{} = {v}", f.raw()))
        })
        .collect();
    lines.push(format!(
        "Onde atual: {}",
        if current.is_empty() {
            "(vazio)".to_string()
        } else {
            current.join("; ")
        }
    ));
    lines.push(String::new());
    lines.push("## Tópicos de regras disponíveis".into());
    if topics.is_empty() {
        lines.push("(nenhum)".into());
    }
    for t in topics {
        let mut line = format!("- {}: {}", t.slug, t.value.title);
        if let Some(d) = t.value.description.as_deref().filter(|d| !d.is_empty()) {
            line.push_str(&format!(" — {d}"));
        }
        line.push_str(&format!(" (paths: {})", t.value.paths.join(", ")));
        lines.push(line);
    }
    lines.extend([
        String::new(),
        "## Resposta".to_string(),
        "- fields: só os campos que você encontrou de verdade (file, route, component, selector).".to_string(),
        "  file é um caminho relativo à raiz de um arquivo que existe. Não invente; se não achou, omita.".to_string(),
        "- rules: slugs da lista acima que o item deve seguir. Só slugs da lista.".to_string(),
        "- reason: uma frase curta dizendo onde encontrou (ex.: Sources/App/View.swift:42).".to_string(),
    ]);
    lines.join("\n")
}

/// Lê o resultado de `--output-format json` do stdout. Falha sem tocar em nada se a chamada falhou ou a
/// resposta não decodifica.
pub fn parse(output: &[u8]) -> Result<Answer, DiscoverError> {
    let text = String::from_utf8_lossy(output);
    let result = text
        .split([
            '\n', '\r', '\u{2028}', '\u{2029}', '\u{0b}', '\u{0c}', '\u{85}',
        ])
        .rev()
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .find(|v| v.get("type").and_then(Value::as_str) == Some("result"))
        .ok_or(DiscoverError::InvalidAnswer)?;
    let subtype = result.get("subtype").and_then(Value::as_str);
    if result.get("is_error").and_then(Value::as_bool) == Some(true) || subtype != Some("success") {
        let message = [
            result.get("result").and_then(Value::as_str),
            result.get("subtype").and_then(Value::as_str),
        ]
        .into_iter()
        .flatten()
        .find(|s| !s.is_empty())
        .unwrap_or("");
        return Err(DiscoverError::Failed(message.to_string()));
    }
    let structured: Option<Vec<u8>> = match result.get("structured_output") {
        Some(v) if !v.is_null() => serde_json::to_vec(v).ok(),
        _ => result
            .get("result")
            .and_then(Value::as_str)
            .map(|s| s.as_bytes().to_vec()),
    };
    structured
        .and_then(|s| serde_json::from_slice::<Answer>(&s).ok())
        .ok_or(DiscoverError::InvalidAnswer)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldChange {
    pub field: Field,
    /// Valor atual; `Some` significa que aceitar substitui.
    pub current: Option<String>,
    pub suggested: String,
    pub reason: Option<String>,
}

impl FieldChange {
    pub fn replaces(&self) -> bool {
        self.current.is_some()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicAddition {
    pub slug: String,
    pub title: String,
    pub reason: Option<String>,
}

/// Sugestões validadas aguardando a escolha do usuário.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Proposal {
    pub fields: Vec<FieldChange>,
    pub topics: Vec<TopicAddition>,
    /// Sugestões descartadas pela validação (mostradas para o usuário saber que existiram).
    pub discarded: Vec<String>,
}

impl Proposal {
    pub fn is_empty(&self) -> bool {
        self.fields.is_empty() && self.topics.is_empty()
    }

    /// Campos que começam marcados: os vazios. Substituir um valor é opt-in.
    pub fn default_fields(&self) -> Vec<Field> {
        self.fields
            .iter()
            .filter(|f| !f.replaces())
            .map(|f| f.field)
            .collect()
    }

    /// Grava os campos escolhidos e acrescenta os tópicos escolhidos (tópicos só são adicionados).
    pub fn apply(&self, chosen: &[Field], chosen_topics: &[String], item: &mut ReviewItem) {
        let mut target = item.target.take().unwrap_or_default();
        for change in self.fields.iter().filter(|c| chosen.contains(&c.field)) {
            change
                .field
                .set(&mut target, Some(change.suggested.clone()));
        }
        item.target = (!target.is_empty()).then_some(target);
        for topic in &self.topics {
            if chosen_topics.contains(&topic.slug) && !item.rules.contains(&topic.slug) {
                item.rules.push(topic.slug.clone());
            }
        }
    }
}

/// Fica só com o que se aplica com segurança: arquivos existentes dentro do projeto, slugs conhecidos
/// ainda não ligados ao item e valores diferentes dos atuais.
pub fn proposal(
    answer: &Answer,
    item: &ReviewItem,
    topics: &[Record<RuleTopic>],
    store: &Store,
) -> Proposal {
    let mut proposal = Proposal::default();
    let mut seen: Vec<Field> = Vec::new();
    for s in &answer.fields {
        let mut value = s.value.trim().to_string();
        if value.is_empty() || seen.contains(&s.field) {
            continue;
        }
        if s.field == Field::File {
            match existing_file(&value, store.root()) {
                Some(f) => value = f,
                None => {
                    proposal
                        .discarded
                        .push(format!("Arquivo não encontrado no projeto: {value}"));
                    continue;
                }
            }
        }
        let current = item.target.as_ref().and_then(|t| s.field.get(t)).cloned();
        seen.push(s.field);
        if current.as_deref() == Some(value.as_str()) {
            continue;
        }
        proposal.fields.push(FieldChange {
            field: s.field,
            current,
            suggested: value,
            reason: s.reason.clone(),
        });
    }
    let candidates = candidate_topics(topics, item);
    let mut added: Vec<&str> = Vec::new();
    for s in &answer.rules {
        let Some(m) = candidates.iter().find(|t| t.slug == s.slug) else {
            if !item.rules.contains(&s.slug) && !topics.iter().any(|t| t.slug == s.slug) {
                proposal
                    .discarded
                    .push(format!("Tópico de regras inexistente: {}", s.slug));
            }
            continue;
        };
        if added.contains(&m.slug.as_str()) {
            continue;
        }
        added.push(&m.slug);
        proposal.topics.push(TopicAddition {
            slug: m.slug.clone(),
            title: m.value.title.clone(),
            reason: s.reason.clone(),
        });
    }
    proposal
}

/// Caminho relativo à raiz de um arquivo regular dentro do projeto, ou `None`.
pub fn existing_file(path: &str, root: &Path) -> Option<String> {
    let relative = relative_to_root(root, path);
    if relative.starts_with('/') {
        return None;
    }
    let full = paths::lexical_normalize(&root.join(&relative));
    let root_norm = paths::lexical_normalize(root);
    let rel = full.strip_prefix(&root_norm).ok()?;
    if !full.is_file() {
        return None;
    }
    Some(rel.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn topic(slug: &str, title: &str, paths: &[&str]) -> Record<RuleTopic> {
        let mut t = RuleTopic::new(title);
        t.paths = paths.iter().map(|s| s.to_string()).collect();
        Record {
            slug: slug.into(),
            value: t,
        }
    }

    fn topics() -> Vec<Record<RuleTopic>> {
        vec![
            topic("geral", "Geral", &[]),
            topic("interface", "Interface", &["Sources/App/**"]),
            topic("core", "Core", &["Sources/Core/**"]),
        ]
    }

    fn output(structured: &str, is_error: bool, subtype: &str) -> Vec<u8> {
        format!(
            r#"{{"type":"result","subtype":"{subtype}","is_error":{is_error},"result":"","structured_output":{structured}}}"#
        )
        .into_bytes()
    }

    #[test]
    fn argumentos_somente_leitura() {
        let args = arguments("politica");
        let at = |k: &str| args[args.iter().position(|a| a == k).unwrap() + 1].clone();
        assert_eq!(at("--tools"), "Read,Grep,Glob");
        assert_eq!(at("--allowedTools"), "Read,Grep,Glob");
        assert!(args.contains(&"--strict-mcp-config".to_string()));
        assert!(args.contains(&"--json-schema".to_string()));
        assert!(!args.iter().any(|a| a.contains("Bash")));
        assert!(!args.contains(&"--dangerously-skip-permissions".to_string()));
    }

    #[test]
    fn prompt_lista_so_candidatos() {
        let all = topics();
        let mut item = ReviewItem::new("fix", "Botão quebrado");
        item.details = Some("Na tela de login".into());
        item.target = Some(ReviewTarget {
            route: Some("/login".into()),
            ..Default::default()
        });
        item.rules = vec!["core".into()];
        let c = candidate_topics(&all, &item);
        assert_eq!(
            c.iter().map(|t| t.slug.as_str()).collect::<Vec<_>>(),
            ["interface"]
        );
        let p = prompt(&item, "Corrigir", &c);
        assert!(p.contains("Título: Botão quebrado"));
        assert!(p.contains("Detalhes: Na tela de login"));
        assert!(p.contains("route = /login"));
        assert!(p.contains("- interface: Interface"));
        assert!(!p.contains("- geral") && !p.contains("- core"));

        let mut on_file = ReviewItem::new("fix", "x");
        on_file.target = Some(ReviewTarget {
            file: Some("Sources/App/View.swift".into()),
            ..Default::default()
        });
        let c = candidate_topics(&all, &on_file);
        assert_eq!(
            c.iter().map(|t| t.slug.as_str()).collect::<Vec<_>>(),
            ["core"]
        );
    }

    #[test]
    fn saida_estruturada() {
        let mut data = b"hook noise\n".to_vec();
        data.extend(output(
            r#"{"fields":[{"field":"file","value":"a.swift","reason":"a.swift:3"}],"rules":[{"slug":"core","reason":"x"}]}"#,
            false,
            "success",
        ));
        let a = parse(&data).unwrap();
        assert_eq!(a.fields[0].value, "a.swift");
        assert_eq!(a.fields[0].reason.as_deref(), Some("a.swift:3"));
        assert_eq!(a.rules[0].slug, "core");
    }

    #[test]
    fn saida_invalida_ou_falha() {
        assert_eq!(parse(b"nao e json"), Err(DiscoverError::InvalidAnswer));
        assert_eq!(
            parse(&output(r#"{"fields":"x"}"#, false, "success")),
            Err(DiscoverError::InvalidAnswer)
        );
        assert_eq!(
            parse(&output("null", true, "error_max_turns")),
            Err(DiscoverError::Failed("error_max_turns".into()))
        );
        assert_eq!(
            DiscoverError::Failed("x".into()).to_string(),
            "O Claude Code não conseguiu descobrir; nada foi alterado.\nx"
        );
        assert_eq!(
            DiscoverError::Failed(String::new()).to_string(),
            "O Claude Code não conseguiu descobrir; nada foi alterado."
        );
    }

    #[test]
    fn resultado_em_texto_quando_sem_structured_output() {
        let line = r#"{"type":"result","subtype":"success","is_error":false,"result":"{\"fields\":[],\"rules\":[]}"}"#;
        assert_eq!(parse(line.as_bytes()).unwrap(), Answer::default());
    }

    #[test]
    fn proposta_descarta_inexistentes() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::init(tmp.path(), "demo", None).unwrap();
        std::fs::create_dir_all(tmp.path().join("Sources/App")).unwrap();
        std::fs::write(tmp.path().join("Sources/App/View.swift"), "x").unwrap();
        let item = ReviewItem::new("fix", "x");
        let answer = Answer {
            fields: vec![
                FieldSuggestion {
                    field: Field::File,
                    value: "Sources/App/Nope.swift".into(),
                    reason: None,
                },
                FieldSuggestion {
                    field: Field::File,
                    value: "../outside.swift".into(),
                    reason: None,
                },
                FieldSuggestion {
                    field: Field::Component,
                    value: "LoginView".into(),
                    reason: Some("View.swift:3".into()),
                },
            ],
            rules: vec![
                TopicSuggestion {
                    slug: "inventado".into(),
                    reason: None,
                },
                TopicSuggestion {
                    slug: "interface".into(),
                    reason: Some("tela".into()),
                },
            ],
        };
        let p = proposal(&answer, &item, &topics(), &store);
        assert_eq!(
            p.fields.iter().map(|f| f.field).collect::<Vec<_>>(),
            [Field::Component]
        );
        assert_eq!(
            p.topics.iter().map(|t| t.slug.as_str()).collect::<Vec<_>>(),
            ["interface"]
        );
        assert_eq!(p.discarded.len(), 3);

        let abs = format!("{}/Sources/App/View.swift", store.root().display());
        let found = Answer {
            fields: vec![FieldSuggestion {
                field: Field::File,
                value: abs,
                reason: None,
            }],
            rules: vec![],
        };
        let p = proposal(&found, &item, &topics(), &store);
        assert_eq!(p.fields[0].suggested, "Sources/App/View.swift");
        let dir = Answer {
            fields: vec![FieldSuggestion {
                field: Field::File,
                value: "Sources/App".into(),
                reason: None,
            }],
            rules: vec![],
        };
        assert!(proposal(&dir, &item, &topics(), &store).fields.is_empty());
    }

    #[test]
    fn substituir_exige_opt_in_e_topicos_so_somam() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::init(tmp.path(), "demo", None).unwrap();
        let mut item = ReviewItem::new("fix", "x");
        item.target = Some(ReviewTarget {
            component: Some("Velho".into()),
            ..Default::default()
        });
        item.rules = vec!["core".into()];
        let answer = Answer {
            fields: vec![
                FieldSuggestion {
                    field: Field::Component,
                    value: "Novo".into(),
                    reason: None,
                },
                FieldSuggestion {
                    field: Field::Route,
                    value: "/login".into(),
                    reason: None,
                },
                FieldSuggestion {
                    field: Field::Selector,
                    value: "".into(),
                    reason: None,
                },
            ],
            rules: vec![
                TopicSuggestion {
                    slug: "core".into(),
                    reason: None,
                },
                TopicSuggestion {
                    slug: "geral".into(),
                    reason: None,
                },
                TopicSuggestion {
                    slug: "interface".into(),
                    reason: None,
                },
            ],
        };
        let p = proposal(&answer, &item, &topics(), &store);
        assert!(
            p.fields
                .iter()
                .find(|f| f.field == Field::Component)
                .unwrap()
                .replaces()
        );
        assert_eq!(p.default_fields(), [Field::Route]);
        assert_eq!(
            p.topics.iter().map(|t| t.slug.as_str()).collect::<Vec<_>>(),
            ["interface"]
        );
        assert!(p.discarded.is_empty());

        p.apply(&p.default_fields(), &[], &mut item);
        assert_eq!(
            item.target,
            Some(ReviewTarget {
                route: Some("/login".into()),
                component: Some("Velho".into()),
                ..Default::default()
            })
        );
        assert_eq!(item.rules, ["core"]);
        p.apply(&[Field::Component], &["interface".into()], &mut item);
        assert_eq!(
            item.target.as_ref().unwrap().component.as_deref(),
            Some("Novo")
        );
        assert_eq!(item.rules, ["core", "interface"]);
    }
}
