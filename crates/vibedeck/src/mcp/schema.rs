//! Gerador de inputSchema equivalente a `schema()` de MCPServer.swift (L197-213).
//!
//! Descrição de parâmetro só é emitida se tiver >= 40 caracteres ou casar a regex do Swift
//! (mantém o orçamento de tokens do contrato).

use serde_json::{Map, Value, json};

/// Parâmetro: nome, tipo (`"array"` = array de strings), descrição (vazia = omitida).
pub struct Prop {
    pub name: &'static str,
    pub ty: &'static str,
    pub description: &'static str,
}

pub fn prop(name: &'static str, ty: &'static str, description: &'static str) -> Prop {
    Prop {
        name,
        ty,
        description,
    }
}

const KEYWORDS: &[&str] = &[
    "padrão", "prefixo", "Só", "só", "Sem", "sem", "pergunte", "confirm", "não", "nunca", "stdin",
    "JSON", "codex", "claude", "provider", "globs", ">=", "vazi",
];

/// Equivale à regex `padrão|prefixo|[|<>{}=0-9≥≤]|Só|só|Sem|sem|pergunte|confirm|não|nunca|stdin|JSON|codex|claude|provider|globs|>=|vazi`.
pub fn explains_contract(description: &str) -> bool {
    description.chars().count() >= 40
        || description
            .chars()
            .any(|c| "|<>{}=≥≤".contains(c) || c.is_ascii_digit())
        || KEYWORDS.iter().any(|k| description.contains(k))
}

/// `required`/`enums`/`custom` como no Swift; `custom` entra primeiro e é sobrescrito por `props`.
pub fn schema(
    props: &[Prop],
    required: &[&str],
    enums: &[(&str, &[&str])],
    custom: &[(&str, Value)],
) -> Value {
    let mut properties = Map::new();
    for (k, v) in custom {
        properties.insert((*k).to_string(), v.clone());
    }
    for p in props {
        let mut o = Map::new();
        o.insert("type".into(), json!(p.ty));
        if !p.description.is_empty() && explains_contract(p.description) {
            o.insert("description".into(), json!(p.description));
        }
        if p.ty == "array" {
            o.insert("items".into(), json!({"type": "string"}));
        }
        if let Some((_, values)) = enums.iter().find(|(n, _)| *n == p.name) {
            o.insert("enum".into(), json!(values));
        }
        properties.insert(p.name.to_string(), Value::Object(o));
    }
    let mut object = Map::new();
    object.insert("type".into(), json!("object"));
    if !properties.is_empty() {
        object.insert("properties".into(), Value::Object(properties));
    }
    if !required.is_empty() {
        object.insert("required".into(), json!(required));
    }
    Value::Object(object)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn omite_descricoes_curtas_sem_palavra_chave() {
        assert!(!explains_contract("arquivo alterado"));
        assert!(!explains_contract(""));
        assert!(explains_contract("claude (padrão)|codex"));
        assert!(explains_contract("limite 20"));
        assert!(explains_contract("só leitura"));
        assert!(explains_contract(&"a".repeat(40)));
        assert!(!explains_contract(&"a".repeat(39)));
    }

    #[test]
    fn gera_schema() {
        let s = schema(
            &[
                prop("title", "string", "titulo"),
                prop("tags", "array", "nunca vazio"),
                prop("status", "string", ""),
            ],
            &["title"],
            &[("status", &["open", "done"])],
            &[],
        );
        assert_eq!(
            s,
            json!({"type":"object","properties":{
                "title":{"type":"string"},
                "tags":{"type":"array","description":"nunca vazio","items":{"type":"string"}},
                "status":{"type":"string","enum":["open","done"]}},
                "required":["title"]})
        );
        assert_eq!(schema(&[], &[], &[], &[]), json!({"type":"object"}));
    }
}
