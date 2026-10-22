//! Emissor VDJSON: `JSONEncoder` do Swift com `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`.
//!
//! Regras (dados.md §2.1 e Apêndice A): 2 espaços por nível, `" : "` entre chave e valor, chaves em ordem de
//! bytes UTF-8, contêiner vazio como `[\n\n<ind>]` / `{\n\n<ind>}`, `/` e não-ASCII crus, controles `< 0x20`
//! como `\u00xx` minúsculo (com `\n \r \t \b \f` curtos) e exatamente um `\n` final.

use serde::Serialize;
use serde_json::Value;

/// Serializa `value` (qualquer `Serialize`) no formato de arquivo do Swift, com `\n` final.
pub fn encode<T: Serialize + ?Sized>(value: &T) -> Result<Vec<u8>, serde_json::Error> {
    let v = serde_json::to_value(value)?;
    Ok(to_vdjson(&v).into_bytes())
}

/// Emite um `Value` no formato de arquivo (com `\n` final).
pub fn to_vdjson(value: &Value) -> String {
    let mut out = String::new();
    write_pretty(&mut out, value, 0);
    out.push('\n');
    out
}

/// Variante compacta (`VDJSON.compactEncoder`): chaves ordenadas, sem espaços, sem `\n` final.
pub fn to_compact(value: &Value) -> String {
    let mut out = String::new();
    write_compact(&mut out, value);
    out
}

fn sorted_entries(map: &serde_json::Map<String, Value>) -> Vec<(&String, &Value)> {
    let mut items: Vec<_> = map.iter().collect();
    items.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    items
}

fn indent(out: &mut String, depth: usize) {
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn write_pretty(out: &mut String, value: &Value, depth: usize) {
    match value {
        Value::Object(map) => {
            if map.is_empty() {
                out.push_str("{\n\n");
                indent(out, depth);
                out.push('}');
                return;
            }
            out.push_str("{\n");
            let items = sorted_entries(map);
            for (i, (k, v)) in items.iter().enumerate() {
                indent(out, depth + 1);
                write_string(out, k);
                out.push_str(" : ");
                write_pretty(out, v, depth + 1);
                if i + 1 < items.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            indent(out, depth);
            out.push('}');
        }
        Value::Array(arr) => {
            if arr.is_empty() {
                out.push_str("[\n\n");
                indent(out, depth);
                out.push(']');
                return;
            }
            out.push_str("[\n");
            for (i, v) in arr.iter().enumerate() {
                indent(out, depth + 1);
                write_pretty(out, v, depth + 1);
                if i + 1 < arr.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            indent(out, depth);
            out.push(']');
        }
        other => write_scalar(out, other),
    }
}

fn write_compact(out: &mut String, value: &Value) {
    match value {
        Value::Object(map) => {
            out.push('{');
            for (i, (k, v)) in sorted_entries(map).into_iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_string(out, k);
                out.push(':');
                write_compact(out, v);
            }
            out.push('}');
        }
        Value::Array(arr) => {
            out.push('[');
            for (i, v) in arr.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_compact(out, v);
            }
            out.push(']');
        }
        other => write_scalar(out, other),
    }
}

fn write_scalar(out: &mut String, value: &Value) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::String(s) => write_string(out, s),
        Value::Array(_) | Value::Object(_) => unreachable!("contêineres tratados pelo chamador"),
    }
}

fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn empty_containers_have_blank_line() {
        let v = json!({"a": [], "b": {}, "c": {"d": []}});
        let expected = "{\n  \"a\" : [\n\n  ],\n  \"b\" : {\n\n  },\n  \"c\" : {\n    \"d\" : [\n\n    ]\n  }\n}\n";
        assert_eq!(to_vdjson(&v), expected);
        assert_eq!(to_vdjson(&json!([])), "[\n\n]\n");
        assert_eq!(to_vdjson(&json!({})), "{\n\n}\n");
    }

    #[test]
    fn keys_sorted_by_bytes() {
        let v = json!({"b": 1, "$schema": "x", "B": 2, "a": 3, "é": 4, "z": 5});
        let s = to_vdjson(&v);
        let keys: Vec<&str> = s
            .lines()
            .filter_map(|l| l.trim_start().strip_prefix('"'))
            .map(|l| l.split('"').next().unwrap())
            .collect();
        assert_eq!(keys, ["$schema", "B", "a", "b", "z", "é"]);
    }

    #[test]
    fn control_characters_and_escapes() {
        let v = json!("a\"b\\c/d\n\r\t\u{8}\u{c}\u{1b}\u{0}\u{1f}\u{7f}");
        assert_eq!(
            to_vdjson(&v),
            "\"a\\\"b\\\\c/d\\n\\r\\t\\b\\f\\u001b\\u0000\\u001f\u{7f}\"\n"
        );
    }

    #[test]
    fn unicode_stays_raw() {
        let v = json!("ação → 🎉 \u{2009} \u{2028} ß");
        assert_eq!(to_vdjson(&v), "\"ação → 🎉 \u{2009} \u{2028} ß\"\n");
    }

    #[test]
    fn scalars_and_nesting() {
        let v = json!({"n": -3, "t": true, "f": false, "l": [1, [2], {"x": "y"}]});
        let expected = "{\n  \"f\" : false,\n  \"l\" : [\n    1,\n    [\n      2\n    ],\n    {\n      \"x\" : \"y\"\n    }\n  ],\n  \"n\" : -3,\n  \"t\" : true\n}\n";
        assert_eq!(to_vdjson(&v), expected);
    }

    #[test]
    fn compact_variant() {
        let v = json!({"b": [1, 2], "a": "x/y"});
        assert_eq!(to_compact(&v), r#"{"a":"x/y","b":[1,2]}"#);
    }

    #[test]
    fn encode_serializable() {
        #[derive(Serialize)]
        struct S {
            z: u8,
            a: &'static str,
        }
        let bytes = encode(&S { z: 1, a: "q" }).unwrap();
        assert_eq!(bytes, b"{\n  \"a\" : \"q\",\n  \"z\" : 1\n}\n");
    }
}
