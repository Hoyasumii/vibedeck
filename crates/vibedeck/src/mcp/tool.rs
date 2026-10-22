//! Definição de tool e registro.

use super::args::Args;
use serde_json::{Value, json};
use std::fmt;
use std::path::PathBuf;
use std::sync::Arc;
use vibedeck_core::model::Author;
use vibedeck_core::rules::Cancellation;

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

/// Canal de notificações do servidor para o cliente (uma mensagem JSON-RPC por chamada).
#[derive(Clone)]
pub struct Notifier(Arc<dyn Fn(Value) + Send + Sync>);

impl Notifier {
    pub fn new(send: impl Fn(Value) + Send + Sync + 'static) -> Self {
        Notifier(Arc::new(send))
    }

    pub fn send(&self, message: Value) {
        (self.0)(message);
    }
}

/// Progresso de uma chamada: só existe no modo app e quando o cliente mandou `_meta.progressToken`.
#[derive(Clone)]
pub struct Progress {
    pub token: Value,
    pub notifier: Notifier,
}

/// Contexto entregue aos handlers: raiz do projeto e acesso ao store do core.
#[derive(Clone)]
pub struct ToolCtx {
    pub root: PathBuf,
    /// `vibedeck mcp --app`: habilita `author` nas tools de criação.
    pub app: bool,
    pub progress: Option<Progress>,
    /// Disparado por `notifications/cancelled` durante a chamada.
    pub cancel: Cancellation,
}

impl ToolCtx {
    pub fn new(root: PathBuf) -> Self {
        ToolCtx {
            root,
            app: false,
            progress: None,
            cancel: Cancellation::new(),
        }
    }

    /// Autoria do que a tool cria: `ai` (padrão); `human` só no modo app, com `author: "human"`.
    pub fn author(&self, args: &Args) -> Result<Author, ToolError> {
        if !self.app {
            return Ok(Author::Ai);
        }
        match args.str("author") {
            None | Some("ai") => Ok(Author::Ai),
            Some("human") => Ok(Author::Human),
            Some(_) => Err(ToolError::invalid_params("author deve ser human ou ai.")),
        }
    }

    /// Envia `notifications/progress` desta chamada (no-op sem `progressToken`). `progress` cresce a cada envio.
    pub fn report_progress(&self, progress: u64, message: &str, extra: Value) {
        let Some(p) = &self.progress else { return };
        let mut params = json!({
            "progressToken": p.token,
            "progress": progress,
            "message": message,
        });
        if let (Some(target), Some(fields)) = (params.as_object_mut(), extra.as_object()) {
            target.extend(fields.clone());
        }
        p.notifier
            .send(json!({"jsonrpc": "2.0", "method": "notifications/progress", "params": params}));
    }

    /// Store do projeto (aberto a cada chamada: arquivos podem mudar entre chamadas).
    pub fn store(&self) -> Result<vibedeck_core::Store, ToolError> {
        vibedeck_core::Store::open(&self.root).map_err(ToolError::from)
    }
}

impl From<vibedeck_core::Error> for ToolError {
    fn from(e: vibedeck_core::Error) -> Self {
        ToolError(e.to_string())
    }
}

/// Resultado JSON de tool no formato VDJSON (pretty, chaves ordenadas), como o Swift.
pub fn json_text<T: serde::Serialize + ?Sized>(value: &T) -> Result<String, ToolError> {
    let bytes = vibedeck_core::json::encode(value).map_err(|e| ToolError(e.to_string()))?;
    let mut text = String::from_utf8_lossy(&bytes).into_owned();
    if text.ends_with('\n') {
        text.pop();
    }
    Ok(text)
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
