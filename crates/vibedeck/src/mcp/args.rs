//! Helpers de argumentos, iguais aos de `MCPHandler.call` (MCPServer.swift L729-761).

use super::tool::ToolError;
use serde_json::{Map, Value};

pub struct Args(pub Map<String, Value>);

impl Args {
    pub fn new(map: Map<String, Value>) -> Self {
        Args(map)
    }

    pub fn raw(&self, key: &str) -> Option<&Value> {
        self.0.get(key)
    }

    /// Só string; string vazia = ausente.
    pub fn str(&self, key: &str) -> Option<&str> {
        self.0
            .get(key)
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
    }

    pub fn req(&self, key: &str) -> Result<&str, ToolError> {
        self.str(key)
            .ok_or_else(|| ToolError::invalid_params(format!("Parâmetro obrigatório: {key}")))
    }

    /// Array JSON (itens string, vazios descartados), string com JSON-array ou CSV; outro tipo = None.
    pub fn list(&self, key: &str) -> Option<Vec<String>> {
        match self.0.get(key)? {
            Value::Array(a) => Some(
                a.iter()
                    .filter_map(Value::as_str)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string)
                    .collect(),
            ),
            Value::String(text) => {
                if let Ok(parsed) = serde_json::from_str::<Vec<String>>(text) {
                    return Some(parsed);
                }
                Some(
                    text.split(',')
                        .map(|s| s.trim_matches([' ', '\t']))
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                        .collect(),
                )
            }
            _ => None,
        }
    }

    /// Inteiro tolerante: número JSON (double truncado) ou texto numérico.
    pub fn int(&self, key: &str) -> Option<i64> {
        match self.0.get(key) {
            Some(Value::Number(n)) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
            _ => self.str(key).and_then(|s| s.parse().ok()),
        }
    }

    /// Inteiro estrito (`.intValue` do SDK): inteiro JSON ou double sem parte fracionária.
    pub fn int_strict(&self, key: &str) -> Option<i64> {
        match self.0.get(key)? {
            Value::Number(n) => n.as_i64().or_else(|| {
                n.as_f64()
                    .filter(|f| f.fract() == 0.0 && f.abs() < 9.2e18)
                    .map(|f| f as i64)
            }),
            _ => None,
        }
    }

    /// Só booleano JSON (string "true" não vale).
    pub fn bool(&self, key: &str) -> Option<bool> {
        self.0.get(key).and_then(Value::as_bool)
    }

    /// Ausente = `must`; senão `must|should`.
    pub fn severity(&self) -> Result<&'static str, ToolError> {
        match self.str("severity") {
            None | Some("must") => Ok("must"),
            Some("should") => Ok("should"),
            Some(s) => Err(ToolError::invalid_params(format!("Severidade inválida: {s}"))),
        }
    }

    /// Ausente = `claude`; senão `claude|codex`.
    pub fn provider(&self) -> Result<&'static str, ToolError> {
        match self.str("provider") {
            None | Some("claude") => Ok("claude"),
            Some("codex") => Ok("codex"),
            Some(v) => Err(ToolError::invalid_params(format!("Provedor inválido: {v}"))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn a(v: Value) -> Args {
        Args::new(v.as_object().unwrap().clone())
    }

    #[test]
    fn str_vazia_e_ausente() {
        let x = a(json!({"a":"","b":"x","c":1}));
        assert_eq!(x.str("a"), None);
        assert_eq!(x.str("b"), Some("x"));
        assert_eq!(x.str("c"), None);
        assert!(x.req("a").unwrap_err().0.contains("Parâmetro obrigatório: a"));
    }

    #[test]
    fn list_tres_formas() {
        let x = a(json!({"a":["x","","y",3],"b":"[\"p\",\"q\"]","c":" m, n ,,o","d":5}));
        assert_eq!(x.list("a").unwrap(), ["x", "y"]);
        assert_eq!(x.list("b").unwrap(), ["p", "q"]);
        assert_eq!(x.list("c").unwrap(), ["m", "n", "o"]);
        assert_eq!(x.list("d"), None);
        assert_eq!(x.list("z"), None);
    }

    #[test]
    fn int_tolerante_e_estrito() {
        let x = a(json!({"a":3,"b":3.9,"c":"7","d":"x","e":4.0}));
        assert_eq!(x.int("a"), Some(3));
        assert_eq!(x.int("b"), Some(3));
        assert_eq!(x.int("c"), Some(7));
        assert_eq!(x.int("d"), None);
        assert_eq!(x.int_strict("a"), Some(3));
        assert_eq!(x.int_strict("b"), None);
        assert_eq!(x.int_strict("c"), None);
        assert_eq!(x.int_strict("e"), Some(4));
    }

    #[test]
    fn bool_severity_provider() {
        let x = a(json!({"t":true,"s":"true","severity":"should","provider":"x"}));
        assert_eq!(x.bool("t"), Some(true));
        assert_eq!(x.bool("s"), None);
        assert_eq!(x.severity().unwrap(), "should");
        assert!(x.provider().unwrap_err().0.contains("Provedor inválido: x"));
        assert_eq!(a(json!({})).severity().unwrap(), "must");
        assert_eq!(a(json!({})).provider().unwrap(), "claude");
    }
}
