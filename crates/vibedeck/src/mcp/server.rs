//! Despacho JSON-RPC 2.0 do servidor MCP (síncrono).

use super::args::Args;
use super::instructions::instructions;
use super::tool::{Tool, ToolCtx};
use serde_json::{Map, Value, json};
use std::path::PathBuf;

pub const SUPPORTED_VERSIONS: [&str; 3] = ["2024-11-05", "2025-03-26", "2025-06-18"];
pub const LATEST_VERSION: &str = "2025-06-18";

pub const PARSE_ERROR: i64 = -32700;
pub const INVALID_REQUEST: i64 = -32600;
pub const METHOD_NOT_FOUND: i64 = -32601;
pub const INVALID_PARAMS: i64 = -32602;
pub const INTERNAL_ERROR: i64 = -32603;
/// Código MCP para recurso inexistente.
#[cfg(test)]
pub const RESOURCE_NOT_FOUND: i64 = -32002;

/// Erro JSON-RPC (código + mensagem).
#[derive(Debug, Clone)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
}

impl RpcError {
    pub fn new(code: i64, message: impl Into<String>) -> Self {
        RpcError {
            code,
            message: message.into(),
        }
    }
}

/// Integração: o core fornece `vibedeck://project`, docs, regras etc. aqui.
pub trait ResourceProvider: Send + Sync {
    /// Itens de `resources/list` (`{name, uri, description?, mimeType?}`).
    fn list(&self) -> Result<Vec<Value>, RpcError>;
    /// Item de `contents` de `resources/read`; URI desconhecida = `RESOURCE_NOT_FOUND`.
    fn read(&self, uri: &str) -> Result<Value, RpcError>;
}

#[cfg(test)]
pub struct NoResources;

#[cfg(test)]
impl ResourceProvider for NoResources {
    fn list(&self) -> Result<Vec<Value>, RpcError> {
        Ok(Vec::new())
    }
    fn read(&self, uri: &str) -> Result<Value, RpcError> {
        Err(RpcError::new(
            RESOURCE_NOT_FOUND,
            format!("Resource not found: {uri}"),
        ))
    }
}

pub struct Server {
    ctx: ToolCtx,
    tools: Vec<Tool>,
    resources: Box<dyn ResourceProvider>,
    version: String,
}

impl Server {
    pub fn new(
        root: PathBuf,
        tools: Vec<Tool>,
        resources: Box<dyn ResourceProvider>,
        version: String,
    ) -> Self {
        Server {
            ctx: ToolCtx { root },
            tools,
            resources,
            version,
        }
    }

    /// Processa uma mensagem; `None` para notificações (nunca respondem).
    pub fn handle(&self, msg: &Value) -> Option<Value> {
        let Some(obj) = msg.as_object() else {
            return Some(error_response(
                Value::Null,
                INVALID_REQUEST,
                "Invalid Request",
            ));
        };
        let id = obj.get("id").filter(|v| !v.is_null()).cloned();
        let Some(method) = obj.get("method").and_then(Value::as_str) else {
            // Respostas de clientes (sem method) são ignoradas; id sem method é requisição inválida.
            return if obj.contains_key("result") || obj.contains_key("error") {
                None
            } else {
                Some(error_response(
                    id.unwrap_or(Value::Null),
                    INVALID_REQUEST,
                    "Invalid Request",
                ))
            };
        };
        let Some(id) = id else {
            return None; // notificação (initialized, cancelled, ...): sem resposta
        };
        let params = obj.get("params").cloned().unwrap_or(Value::Null);
        Some(match self.dispatch(method, &params) {
            Ok(result) => json!({"jsonrpc": "2.0", "id": id, "result": result}),
            Err(e) => error_response(id, e.code, &e.message),
        })
    }

    fn dispatch(&self, method: &str, params: &Value) -> Result<Value, RpcError> {
        match method {
            "initialize" => self.initialize(params),
            "ping" => Ok(json!({})),
            "tools/list" => {
                Ok(json!({"tools": self.tools.iter().map(Tool::listing).collect::<Vec<_>>()}))
            }
            "tools/call" => self.call_tool(params),
            "resources/list" => Ok(json!({"resources": self.resources.list()?})),
            "resources/read" => {
                let uri = params
                    .get("uri")
                    .and_then(Value::as_str)
                    .ok_or_else(|| RpcError::new(INVALID_PARAMS, "Invalid params: uri"))?;
                Ok(json!({"contents": [self.resources.read(uri)?]}))
            }
            _ => Err(RpcError::new(
                METHOD_NOT_FOUND,
                format!("Method not found: {method}"),
            )),
        }
    }

    fn initialize(&self, params: &Value) -> Result<Value, RpcError> {
        let requested = params
            .get("protocolVersion")
            .and_then(Value::as_str)
            .ok_or_else(|| RpcError::new(INVALID_PARAMS, "Invalid params: protocolVersion"))?;
        let version = if SUPPORTED_VERSIONS.contains(&requested) {
            requested
        } else {
            LATEST_VERSION
        };
        Ok(json!({
            "protocolVersion": version,
            "capabilities": {
                "tools": {"listChanged": false},
                "resources": {"subscribe": false, "listChanged": false},
            },
            "serverInfo": {"name": "vibedeck", "version": self.version},
            "instructions": instructions(&self.ctx.root.to_string_lossy()),
        }))
    }

    fn call_tool(&self, params: &Value) -> Result<Value, RpcError> {
        let bad = |d: &str| RpcError::new(INVALID_PARAMS, format!("Invalid params: {d}"));
        let name = params
            .get("name")
            .and_then(Value::as_str)
            .ok_or_else(|| bad("name"))?;
        let arguments = match params.get("arguments") {
            None | Some(Value::Null) => Map::new(),
            Some(Value::Object(m)) => m.clone(),
            Some(_) => return Err(bad("arguments")),
        };
        let outcome = match self.tools.iter().find(|t| t.name == name) {
            None => Err(format!("Method not found: Tool desconhecida: {name}")),
            Some(tool) => {
                let args = Args::new(arguments);
                let call = std::panic::AssertUnwindSafe(|| (tool.handler)(&self.ctx, &args));
                match std::panic::catch_unwind(call) {
                    Ok(r) => r.map_err(|e| e.0),
                    Err(_) => Err(format!("Falha interna na ferramenta {name}")),
                }
            }
        };
        let (text, is_error) = match outcome {
            Ok(t) => (t, false),
            Err(t) => (t, true),
        };
        Ok(json!({"content": [{"type": "text", "text": text}], "isError": is_error}))
    }
}

pub fn error_response(id: Value, code: i64, message: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mcp::schema::{prop, schema};
    use crate::mcp::tool::ToolError;

    fn server() -> Server {
        let echo = Tool::new(
            "echo",
            "",
            schema(&[prop("text", "string", "")], &["text"], &[], &[]),
            |_, a| a.req("text").map(str::to_string),
        )
        .read_only();
        let boom = Tool::new("boom", "x", schema(&[], &[], &[], &[]), |_, _| {
            Err(ToolError::new("falhou"))
        });
        Server::new(
            "/p".into(),
            vec![echo, boom],
            Box::new(NoResources),
            "9.9.9".into(),
        )
    }

    fn req(method: &str, params: Value) -> Value {
        json!({"jsonrpc":"2.0","id":1,"method":method,"params":params})
    }

    #[test]
    fn negocia_versao() {
        let s = server();
        for (asked, got) in [
            ("2024-11-05", "2024-11-05"),
            ("2025-03-26", "2025-03-26"),
            ("2025-06-18", "2025-06-18"),
            ("1999-01-01", "2025-06-18"),
        ] {
            let r = s
                .handle(&req("initialize", json!({"protocolVersion": asked})))
                .unwrap();
            assert_eq!(r["result"]["protocolVersion"], got);
            assert_eq!(
                r["result"]["serverInfo"],
                json!({"name":"vibedeck","version":"9.9.9"})
            );
            assert_eq!(r["result"]["capabilities"]["tools"]["listChanged"], false);
            assert_eq!(r["result"]["capabilities"]["resources"]["subscribe"], false);
        }
    }

    #[test]
    fn tools_list_e_call() {
        let s = server();
        let l = s.handle(&req("tools/list", Value::Null)).unwrap();
        assert_eq!(l["result"]["tools"][0]["description"], "");
        assert_eq!(l["result"]["tools"][0]["annotations"]["readOnlyHint"], true);
        assert!(l["result"]["tools"][1].get("annotations").is_none());
        let ok = s
            .handle(&req(
                "tools/call",
                json!({"name":"echo","arguments":{"text":"oi"}}),
            ))
            .unwrap();
        assert_eq!(
            ok["result"],
            json!({"content":[{"type":"text","text":"oi"}],"isError":false})
        );
        let miss = s
            .handle(&req("tools/call", json!({"name":"echo"})))
            .unwrap();
        assert_eq!(miss["result"]["isError"], true);
        let boom = s
            .handle(&req("tools/call", json!({"name":"boom"})))
            .unwrap();
        assert_eq!(boom["result"]["content"][0]["text"], "falhou");
        let unk = s
            .handle(&req("tools/call", json!({"name":"nope"})))
            .unwrap();
        assert_eq!(unk["result"]["isError"], true);
        assert!(unk.get("error").is_none());
    }

    #[test]
    fn notificacoes_metodos_e_recursos() {
        let s = server();
        assert!(
            s.handle(&json!({"jsonrpc":"2.0","method":"notifications/initialized"}))
                .is_none()
        );
        assert!(s.handle(&json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}})).is_none());
        assert!(
            s.handle(&json!({"jsonrpc":"2.0","method":"nope"}))
                .is_none()
        );
        assert_eq!(
            s.handle(&req("ping", Value::Null)).unwrap()["result"],
            json!({})
        );
        assert_eq!(
            s.handle(&req("x/y", Value::Null)).unwrap()["error"]["code"],
            -32601
        );
        assert_eq!(
            s.handle(&req("resources/list", Value::Null)).unwrap()["result"]["resources"],
            json!([])
        );
        assert!(
            s.handle(&req("resources/read", json!({"uri":"vibedeck://x"})))
                .unwrap()["error"]["code"]
                .is_i64()
        );
    }
}
