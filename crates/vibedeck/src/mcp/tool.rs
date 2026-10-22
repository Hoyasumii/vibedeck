//! Definição de tool e registro.

use super::args::Args;
use serde_json::{Value, json};
use std::fmt;
use std::path::PathBuf;

/// Erro de tool: sempre vira `isError:true` com este texto.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolError(pub String);

impl ToolError {
    pub fn new(msg: impl Into<String>) -> Self {
        ToolError(msg.into())
    }
    /// Equivale a `MCPError.invalidParams(detail)` do SDK Swift.
    pub fn invalid_params(detail: impl fmt::Display) -> Self {
        ToolError(format!("Invalid params: {detail}"))
    }
}

impl fmt::Display for ToolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ToolError {}

impl From<String> for ToolError {
    fn from(s: String) -> Self {
        ToolError(s)
    }
}

/// Contexto entregue aos handlers. Integração: aqui entra o `ProjectStore` do core.
pub struct ToolCtx {
    pub root: PathBuf,
}

pub type Handler = Box<dyn Fn(&ToolCtx, &Args) -> Result<String, ToolError> + Send + Sync>;

pub struct Tool {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
    /// `annotations.readOnlyHint = true`.
    pub read_only: bool,
    pub handler: Handler,
}

impl Tool {
    pub fn new(
        name: &str,
        description: &str,
        input_schema: Value,
        handler: impl Fn(&ToolCtx, &Args) -> Result<String, ToolError> + Send + Sync + 'static,
    ) -> Self {
        Tool {
            name: name.to_string(),
            description: description.to_string(),
            input_schema,
            read_only: false,
            handler: Box::new(handler),
        }
    }

    pub fn read_only(mut self) -> Self {
        self.read_only = true;
        self
    }

    /// Entrada de `tools/list`; descrição ausente é string vazia, nunca null.
    pub fn listing(&self) -> Value {
        let mut v = json!({
            "name": self.name,
            "description": self.description,
            "inputSchema": self.input_schema,
        });
        if self.read_only {
            v["annotations"] = json!({"readOnlyHint": true});
        }
        v
    }
}
