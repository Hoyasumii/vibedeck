//! Codex local: cliente JSON-RPC do `codex app-server` (CodexRPC.swift), exploração somente leitura
//! (CodexReadOnly.swift), ferramentas de leitura (CodexReadTools.swift) e consultas (limites, modelos, skills).
//!
//! Síncrono: um thread lê o stdout do processo e entrega mensagens por canal; as chamadas bloqueiam com prazo.

use std::collections::{BTreeMap, HashSet, VecDeque};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{Receiver, RecvTimeoutError, channel};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{Map, Value, json};

use super::provider::{self, Provider};
use super::usage::TokenUsage;
use super::{AiError, Result, context, graphemes};
use crate::model::ProviderSettings;

/// Prazo das requisições comuns (30 s no Swift).
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// `VIBEDECK_AI_TIMEOUT_SECS` (variável de teste) substitui todos os prazos de IA.
pub fn timeout_override() -> Option<Duration> {
    let secs: f64 = std::env::var("VIBEDECK_AI_TIMEOUT_SECS")
        .ok()?
        .parse()
        .ok()?;
    (secs > 0.0).then(|| Duration::from_secs_f64(secs))
}

enum Incoming {
    Message(Value),
    Closed,
}

/// Uma conexão local com o app-server. Sem listener de rede nem chave de API.
pub struct CodexRpc {
    child: Child,
    stdin: Option<ChildStdin>,
    rx: Receiver<Incoming>,
    backlog: VecDeque<Value>,
    stderr_tail: Arc<Mutex<String>>,
    stderr_thread: Option<std::thread::JoinHandle<()>>,
    sequence: i64,
    request_timeout: Duration,
    closed: bool,
}

impl CodexRpc {
    /// Inicia `codex app-server --stdio` em `root` e faz o handshake `initialize`/`initialized`.
    pub fn start(root: &Path) -> Result<CodexRpc> {
        let exe = Provider::Codex
            .executable()
            .ok_or(AiError::CodexUnavailable)?;
        CodexRpc::start_with(root, &exe, &["app-server", "--stdio"], &[])
    }

    /// Como `start`, com executável, argumentos e variáveis de ambiente extras explícitos.
    pub fn start_with(
        root: &Path,
        exe: &Path,
        args: &[&str],
        env: &[(&str, &str)],
    ) -> Result<CodexRpc> {
        let mut cmd = Command::new(exe);
        cmd.args(args)
            .process_group(0)
            .envs(env.iter().copied())
            .current_dir(root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let dir = exe.parent().map(|p| p.to_string_lossy().into_owned());
        let child_path = provider::child_path();
        cmd.env(
            "PATH",
            match dir {
                Some(d) => format!("{d}:{child_path}"),
                None => child_path,
            },
        );
        let mut child = cmd
            .spawn()
            .map_err(|e| AiError::CodexServer(e.to_string()))?;
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().ok_or(AiError::CodexDisconnected)?;
        let stderr = child.stderr.take().ok_or(AiError::CodexDisconnected)?;
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(|l| l.ok()) {
                if let Ok(v) = serde_json::from_str::<Value>(&line)
                    && tx.send(Incoming::Message(v)).is_err()
                {
                    return;
                }
            }
            let _ = tx.send(Incoming::Closed);
        });
        let tail = Arc::new(Mutex::new(String::new()));
        let tail2 = Arc::clone(&tail);
        let stderr_thread = std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(|l| l.ok()) {
                let mut t = tail2.lock().unwrap_or_else(|e| e.into_inner());
                t.push_str(&line);
                t.push('\n');
                if t.len() > 4000 {
                    let cut = t.len() - 4000;
                    let cut = (cut..=t.len())
                        .find(|i| t.is_char_boundary(*i))
                        .unwrap_or(0);
                    t.drain(..cut);
                }
            }
        });
        let mut rpc = CodexRpc {
            child,
            stdin,
            rx,
            backlog: VecDeque::new(),
            stderr_tail: tail,
            stderr_thread: Some(stderr_thread),
            sequence: 0,
            request_timeout: timeout_override().unwrap_or(REQUEST_TIMEOUT),
            closed: false,
        };
        rpc.request(
            "initialize",
            json!({
                "clientInfo": {"name": "vibedeck", "title": "VibeDeck", "version": "1.0"},
                "capabilities": {"experimentalApi": true}
            }),
        )?;
        rpc.notify("initialized", json!({}))?;
        Ok(rpc)
    }

    fn write(&mut self, value: &Value) -> Result<()> {
        let stdin = self.stdin.as_mut().ok_or(AiError::CodexDisconnected)?;
        let mut line = serde_json::to_vec(value).map_err(|_| AiError::CodexInvalidResponse)?;
        line.push(b'\n');
        stdin
            .write_all(&line)
            .and_then(|_| stdin.flush())
            .map_err(|_| AiError::CodexDisconnected)
    }

    /// Por que o processo caiu: o fim do stderr ou o código de saída. Espera um instante o processo sair.
    fn detail(&mut self) -> String {
        let deadline = Instant::now() + Duration::from_secs(2);
        let status = loop {
            match self.child.try_wait() {
                Ok(Some(status)) => break Some(status),
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                _ => break None,
            }
        };
        if status.is_some()
            && let Some(thread) = self.stderr_thread.take()
        {
            let _ = thread.join();
        }
        let tail = self
            .stderr_tail
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .trim()
            .to_string();
        if !tail.is_empty() {
            return tail;
        }
        match status.and_then(|s| s.code()) {
            Some(code) => format!("Conexão encerrada ({code})."),
            None => "Conexão encerrada.".to_string(),
        }
    }

    pub fn notify(&mut self, method: &str, params: Value) -> Result<()> {
        self.write(&json!({"method": method, "params": params}))
    }

    /// Envia a requisição e espera a resposta. Mensagens que chegam no meio vão para `next_message`.
    pub fn request(&mut self, method: &str, params: Value) -> Result<Value> {
        if self.stdin.is_none() {
            return Err(AiError::CodexDisconnected);
        }
        self.sequence += 1;
        let id = self.sequence;
        match self.write(&json!({"id": id, "method": method, "params": params})) {
            Ok(()) => {}
            Err(AiError::CodexDisconnected) => {
                self.closed = true;
                return Err(AiError::CodexServer(self.detail()));
            }
            Err(e) => return Err(e),
        }
        let deadline = Instant::now() + self.request_timeout;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.rx.recv_timeout(left) {
                Ok(Incoming::Message(msg)) => {
                    if msg.get("method").is_some() {
                        self.backlog.push_back(msg);
                    } else if msg.get("id").and_then(Value::as_i64) == Some(id) {
                        if let Some(err) = msg.get("error").filter(|e| !e.is_null()) {
                            let text = err
                                .get("message")
                                .and_then(Value::as_str)
                                .map(str::to_string)
                                .unwrap_or_else(|| err.to_string());
                            return Err(AiError::CodexServer(text));
                        }
                        return Ok(msg.get("result").cloned().unwrap_or(Value::Null));
                    }
                }
                Ok(Incoming::Closed) | Err(RecvTimeoutError::Disconnected) => {
                    self.closed = true;
                    return Err(AiError::CodexServer(self.detail()));
                }
                Err(RecvTimeoutError::Timeout) => {
                    return Err(AiError::CodexTimeout(method.to_string()));
                }
            }
        }
    }

    /// Próxima notificação ou requisição do servidor; `Ok(None)` = prazo esgotado.
    pub fn next_message(&mut self, deadline: Instant) -> Result<Option<Value>> {
        if let Some(m) = self.backlog.pop_front() {
            return Ok(Some(m));
        }
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.rx.recv_timeout(left) {
                Ok(Incoming::Message(m)) => {
                    if m.get("method").is_some() {
                        return Ok(Some(m));
                    }
                }
                Ok(Incoming::Closed) | Err(RecvTimeoutError::Disconnected) => {
                    self.closed = true;
                    return Err(AiError::CodexServer(self.detail()));
                }
                Err(RecvTimeoutError::Timeout) => return Ok(None),
            }
        }
    }

    pub fn respond(&mut self, id: &Value, result: Value) -> Result<()> {
        self.write(&json!({"id": id, "result": result}))
    }

    pub fn reject(&mut self, id: &Value, message: &str) {
        let _ = self.write(&json!({"id": id, "error": {"code": -32601, "message": message}}));
    }

    pub fn stop(&mut self) {
        self.stdin = None;
        if !self.closed {
            // o app-server pode ter filhos: derruba o grupo inteiro
            // SAFETY: `killpg` só envia um sinal ao grupo criado em `start_with`.
            unsafe { libc::killpg(self.child.id() as i32, libc::SIGKILL) };
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

impl Drop for CodexRpc {
    fn drop(&mut self) {
        self.stop();
    }
}

// ---- consultas -----------------------------------------------------------------------------------

/// `account/rateLimits/read` (JSON cru da resposta).
pub fn limits(root: &Path) -> Result<Value> {
    let mut rpc = CodexRpc::start(root)?;
    rpc.request("account/rateLimits/read", json!({}))
}

#[derive(Debug, Clone, PartialEq)]
pub struct RateLimit {
    pub id: String,
    pub used_percent: f64,
    pub minutes: f64,
    pub resets_at: Option<f64>,
}

impl RateLimit {
    pub fn list(response: &Value) -> Vec<RateLimit> {
        let buckets: BTreeMap<String, Value> = match response
            .get("rateLimitsByLimitId")
            .and_then(Value::as_object)
        {
            Some(o) => o.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            None => BTreeMap::from([(
                "codex".to_string(),
                response.get("rateLimits").cloned().unwrap_or(Value::Null),
            )]),
        };
        let mut out = Vec::new();
        for (key, bucket) in &buckets {
            for window in ["primary", "secondary"] {
                let Some(value) = bucket.get(window) else {
                    continue;
                };
                let Some(used) = value.get("usedPercent").and_then(Value::as_f64) else {
                    continue;
                };
                out.push(RateLimit {
                    id: format!("{key} · {window}"),
                    used_percent: used,
                    minutes: value
                        .get("windowDurationMins")
                        .and_then(Value::as_f64)
                        .unwrap_or(0.0),
                    resets_at: value.get("resetsAt").and_then(Value::as_f64),
                });
            }
        }
        out
    }

    /// `"<id>: <N>% · <min> min"` (inteiros truncados, como `Int(...)` no Swift).
    pub fn line(&self) -> String {
        format!(
            "{}: {}% · {} min",
            self.id, self.used_percent as i64, self.minutes as i64
        )
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Model {
    pub id: String,
    pub title: String,
    pub efforts: Vec<String>,
    pub is_default: bool,
}

impl Model {
    pub fn list(response: &Value) -> Vec<Model> {
        response
            .get("data")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|m| {
                let id = m.get("model")?.as_str()?;
                if m.get("hidden").and_then(Value::as_bool) == Some(true) {
                    return None;
                }
                Some(Model {
                    id: id.to_string(),
                    title: m
                        .get("displayName")
                        .and_then(Value::as_str)
                        .unwrap_or(id)
                        .to_string(),
                    efforts: m
                        .get("supportedReasoningEfforts")
                        .and_then(Value::as_array)
                        .map(|a| {
                            a.iter()
                                .filter_map(|e| e.get("reasoningEffort")?.as_str())
                                .map(str::to_string)
                                .collect()
                        })
                        .unwrap_or_default(),
                    is_default: m.get("isDefault").and_then(Value::as_bool).unwrap_or(false),
                })
            })
            .collect()
    }
}

/// Caminhos de `SKILL.md` das skills do Codex (`skills/list` do app-server) e avisos das inválidas. Skills
/// do projeto vêm primeiro: numa colisão de nome, a do projeto vence.
pub fn skill_paths(root: &Path) -> Result<(Vec<PathBuf>, Vec<String>)> {
    let exe = Provider::Codex
        .executable()
        .ok_or(AiError::CodexUnavailable)?;
    skill_paths_with(root, &exe, &[])
}

/// `skill_paths` com executável e ambiente explícitos (testes).
pub fn skill_paths_with(
    root: &Path,
    exe: &Path,
    env: &[(&str, &str)],
) -> Result<(Vec<PathBuf>, Vec<String>)> {
    let mut rpc = CodexRpc::start_with(root, exe, &["app-server", "--stdio"], env)?;
    let response = rpc.request(
        "skills/list",
        json!({"cwds": [root.to_string_lossy()], "forceReload": true}),
    )?;
    let mut paths: Vec<PathBuf> = Vec::new();
    let mut warnings = Vec::new();
    for entry in response
        .get("data")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        for error in entry
            .get("errors")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            warnings.push(format!(
                "{}: {}",
                error.get("path").and_then(Value::as_str).unwrap_or("skill"),
                error
                    .get("message")
                    .and_then(Value::as_str)
                    .unwrap_or("inválida")
            ));
        }
        for skill in entry
            .get("skills")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if skill.get("enabled").and_then(Value::as_bool) == Some(false) {
                continue;
            }
            if let Some(p) = skill.get("path").and_then(Value::as_str) {
                paths.push(PathBuf::from(p));
            }
        }
    }
    let prefix = format!("{}/", root.to_string_lossy());
    paths.sort_by(|a, b| {
        let (ap, bp) = (
            a.to_string_lossy().starts_with(&prefix),
            b.to_string_lossy().starts_with(&prefix),
        );
        bp.cmp(&ap).then_with(|| a.cmp(b))
    });
    Ok((paths, warnings))
}

// ---- ferramentas de leitura -----------------------------------------------------------------------

const BYTE_LIMIT: u64 = 2_000_000;
const OUTPUT_LIMIT: usize = 16_000;
const FILE_LIMIT: usize = 20_000;

/// `dynamicTools` do thread: só Read, Glob e Grep.
pub fn read_tool_specs() -> Value {
    let string = json!({"type": "string"});
    let integer = json!({"type": "integer", "minimum": 1});
    let spec = |name: &str, description: &str, props: Value, required: Value| {
        json!({"type": "function", "name": name, "description": description,
            "inputSchema": {"type": "object", "properties": props, "required": required, "additionalProperties": false}})
    };
    json!([
        spec(
            "Read",
            "Leia um arquivo UTF-8 do projeto, com linhas numeradas. Use offset/limit para trechos.",
            json!({"path": string, "offset": integer, "limit": integer}),
            json!(["path"])
        ),
        spec(
            "Glob",
            "Liste arquivos do projeto por glob. Use offset/limit para paginar.",
            json!({"pattern": string, "offset": integer, "limit": integer}),
            json!(["pattern"])
        ),
        spec(
            "Grep",
            "Busque texto literal nos arquivos do projeto. Restrinja glob para buscas grandes; saída com arquivo:linha.",
            json!({"pattern": string, "glob": string}),
            json!(["pattern"])
        )
    ])
}

pub use crate::ideas::{glob_matches, project_files};

fn invalid(message: impl Into<String>) -> AiError {
    AiError::DiscoverFailed(message.into())
}

fn positive(arguments: &Value, key: &str, default: i64, maximum: i64) -> Result<i64> {
    let Some(value) = arguments.get(key) else {
        return Ok(default);
    };
    match value.as_f64() {
        Some(n) if n.is_finite() && n >= 1.0 && n.round() == n && n <= maximum as f64 => {
            Ok(n as i64)
        }
        _ => Err(invalid(format!(
            "{key} deve ser um inteiro entre 1 e {maximum}."
        ))),
    }
}

fn confined_file(path: &str, root: &Path) -> Result<PathBuf> {
    let base = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
    let joined = if path.starts_with('/') {
        PathBuf::from(path)
    } else {
        base.join(path)
    };
    let url = crate::paths::canonical(&joined);
    if !url.starts_with(&base) || url == base {
        return Err(invalid(format!(
            "Arquivo fora do projeto ou indisponível: {path}"
        )));
    }
    let meta = std::fs::metadata(&url)
        .map_err(|_| invalid(format!("Arquivo fora do projeto ou indisponível: {path}")))?;
    if !meta.is_file() || meta.len() > BYTE_LIMIT {
        return Err(invalid(format!(
            "Leia um arquivo de texto regular de até 2 MB: {path}"
        )));
    }
    Ok(url)
}

fn read_text(url: &Path) -> Result<String> {
    let name = url
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let bad = || invalid(format!("Arquivo não é texto UTF-8 de até 2 MB: {name}"));
    let data = std::fs::read(url).map_err(|_| bad())?;
    if data.len() as u64 > BYTE_LIMIT || data.contains(&0) {
        return Err(bad());
    }
    String::from_utf8(data).map_err(|_| bad())
}

/// Executa uma ferramenta de leitura; nunca grava nem roda comandos.
pub fn execute_read_tool(root: &Path, tool: &str, arguments: &Value) -> Result<String> {
    if !["Read", "Glob", "Grep"].contains(&tool) {
        return Err(invalid(format!("Ferramenta não permitida: {tool}")));
    }
    let files = || {
        let mut all: HashSet<String> = project_files(root, FILE_LIMIT).into_iter().collect();
        let data = root.join(".vibedeck");
        for f in project_files(&data, FILE_LIMIT) {
            all.insert(format!(".vibedeck/{f}"));
        }
        let mut v: Vec<String> = all.into_iter().collect();
        v.sort();
        v
    };
    let text_arg = |key: &str| arguments.get(key).and_then(Value::as_str);
    match tool {
        "Read" => {
            let path =
                text_arg("path").ok_or_else(|| invalid("Informe path para ler um arquivo."))?;
            let text = read_text(&confined_file(path, root)?)?;
            let offset = positive(arguments, "offset", 1, BYTE_LIMIT as i64)?;
            let limit = positive(arguments, "limit", 200, 500)?;
            let lines: Vec<&str> = text.split('\n').collect();
            let start = ((offset - 1) as usize).min(lines.len());
            let end = (start + limit as usize).min(lines.len());
            Ok(lines[start..end]
                .iter()
                .enumerate()
                .map(|(i, l)| format!("{path}:{}:{l}", start + i + 1))
                .collect::<Vec<_>>()
                .join("\n"))
        }
        "Glob" => {
            let pattern = text_arg("pattern")
                .ok_or_else(|| invalid("Informe pattern para listar arquivos."))?;
            let offset = positive(arguments, "offset", 1, BYTE_LIMIT as i64)?;
            let limit = positive(arguments, "limit", 200, 1000)?;
            let matches: Vec<String> = files()
                .into_iter()
                .filter(|f| glob_matches(pattern, f))
                .collect();
            let start = ((offset - 1) as usize).min(matches.len());
            let end = (start + limit as usize).min(matches.len());
            Ok(format!(
                "{}\n{} arquivo(s); próximo offset: {}.",
                matches[start..end].join("\n"),
                matches.len(),
                end + 1
            ))
        }
        _ => {
            let pattern = text_arg("pattern")
                .filter(|p| !p.is_empty() && p.chars().count() <= 1000)
                .ok_or_else(|| {
                    invalid("Informe pattern com 1 a 1000 caracteres para busca literal.")
                })?;
            let glob = text_arg("glob").unwrap_or("**");
            let (mut matches, mut bytes, mut count) = (Vec::<String>::new(), 0usize, 0usize);
            let deadline = Instant::now() + Duration::from_secs(2);
            for path in files() {
                if !glob_matches(glob, &path) {
                    continue;
                }
                if Instant::now() > deadline
                    || bytes >= 10_000_000
                    || count >= 1000
                    || matches.len() >= 100
                {
                    matches.push("Busca limitada; refine glob ou pattern.".to_string());
                    break;
                }
                count += 1;
                let Ok(url) = confined_file(&path, root) else {
                    continue;
                };
                let Ok(text) = read_text(&url) else {
                    continue;
                };
                bytes += text.len();
                for (index, line) in text.split('\n').enumerate() {
                    if line.contains(pattern) {
                        let shown: String =
                            graphemes::clusters(line).into_iter().take(1000).collect();
                        matches.push(format!("{path}:{}:{shown}", index + 1));
                        if matches.len() >= 100 {
                            break;
                        }
                    }
                }
            }
            Ok(if matches.is_empty() {
                "Nenhuma ocorrência.".to_string()
            } else {
                matches.join("\n")
            })
        }
    }
}

/// Resposta de `item/tool/call`: `success` + `contentItems` (texto limitado a 16 000 caracteres).
pub fn read_tool_response(root: &Path, tool: &str, arguments: &Value) -> Value {
    let (text, success) = match execute_read_tool(root, tool, arguments) {
        Ok(t) => (t, true),
        Err(e) => (e.to_string(), false),
    };
    let shown: String = graphemes::clusters(&text)
        .into_iter()
        .take(OUTPUT_LIMIT)
        .collect();
    json!({"success": success, "contentItems": [{"type": "inputText", "text": shown}]})
}

// ---- exploração somente leitura -------------------------------------------------------------------

/// `additionalProperties: false` em todo objeto do schema (o app-server exige schema estrito).
pub fn strict_schema(value: &Value) -> Value {
    match value {
        Value::Object(o) => {
            let mut out: Map<String, Value> = o
                .iter()
                .map(|(k, v)| (k.clone(), strict_schema(v)))
                .collect();
            if o.get("type").and_then(Value::as_str) == Some("object") {
                out.insert("additionalProperties".into(), Value::Bool(false));
            }
            Value::Object(out)
        }
        Value::Array(a) => Value::Array(a.iter().map(strict_schema).collect()),
        other => other.clone(),
    }
}

/// Desliga MCP externos e o shell: a chamada só enxerga as ferramentas de leitura.
pub fn read_only_overrides(config: &Value) -> Map<String, Value> {
    let mut overrides = Map::new();
    if let Some(servers) = config
        .get("config")
        .and_then(|c| c.get("mcp_servers"))
        .and_then(Value::as_object)
    {
        for name in servers.keys() {
            overrides.insert(format!("mcp_servers.{name}.enabled"), Value::Bool(false));
        }
    }
    overrides.insert("features.shell_tool".into(), Value::Bool(false));
    overrides.insert("features.unified_exec".into(), Value::Bool(false));
    overrides
}

/// Junta deltas de mensagens do agente sem duplicar o texto final (`CodexEventStream`).
#[derive(Default)]
struct EventStream {
    texts: BTreeMap<String, String>,
    completed: HashSet<String>,
    final_text: Option<String>,
}

impl EventStream {
    /// Texto a acrescentar à saída, se houver.
    fn event(&mut self, method: &str, params: &Value) -> Option<String> {
        let item = params.get("item").cloned().unwrap_or(Value::Null);
        let id = params
            .get("itemId")
            .and_then(Value::as_str)
            .or_else(|| item.get("id").and_then(Value::as_str))
            .unwrap_or("")
            .to_string();
        if method == "item/agentMessage/delta" {
            if self.completed.contains(&id) {
                return None;
            }
            let delta = params.get("delta").and_then(Value::as_str).unwrap_or("");
            self.texts.entry(id).or_default().push_str(delta);
            return Some(delta.to_string());
        }
        if method == "item/completed"
            && item.get("type").and_then(Value::as_str) == Some("agentMessage")
        {
            if !self.completed.insert(id.clone()) {
                return None;
            }
            let text = item.get("text").and_then(Value::as_str).unwrap_or("");
            let previous = self.texts.get(&id).cloned().unwrap_or_default();
            if item.get("phase").and_then(Value::as_str) == Some("final_answer") {
                self.final_text = Some(text.to_string());
            }
            self.texts.insert(id, text.to_string());
            let suffix = text.strip_prefix(previous.as_str())?;
            return (!suffix.is_empty()).then(|| suffix.to_string());
        }
        None
    }
}

#[derive(Debug, Clone)]
pub struct ReadOnlyOutput {
    pub text: String,
    pub tokens: TokenUsage,
    pub model: Option<String>,
}

/// Chamada estruturada isolada, só leitura: thread efêmera, sem aprovações, MCP e shell desligados, e as
/// ferramentas Read/Glob/Grep do VibeDeck como `dynamicTools`.
pub fn run_read_only(
    root: &Path,
    prompt: &str,
    schema: &Value,
    timeout: Duration,
    settings: &ProviderSettings,
) -> Result<ReadOnlyOutput> {
    let timeout = timeout_override().unwrap_or(timeout);
    let deadline = Instant::now() + timeout;
    let mut rpc = CodexRpc::start(root)?;
    let config = rpc.request("config/read", json!({"includeLayers": false}))?;
    let mut params = json!({
        "cwd": root.to_string_lossy(),
        "ephemeral": true,
        "approvalPolicy": "never",
        "sandbox": "read-only",
        "config": Value::Object(read_only_overrides(&config)),
        "developerInstructions": context::INSTRUCTIONS,
        "dynamicTools": read_tool_specs(),
        "allowProviderModelFallback": false,
    });
    if let Some(model) = &settings.model {
        params["model"] = json!(model);
    }
    let response = rpc.request("thread/start", params)?;
    let model = response
        .get("model")
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| settings.model.clone());
    if settings.model.is_some() || settings.effort.is_some() {
        let mut models: Vec<Model> = Vec::new();
        let mut cursor: Option<String> = None;
        loop {
            let mut p = json!({"limit": 100});
            if let Some(c) = &cursor {
                p["cursor"] = json!(c);
            }
            let page = rpc.request("model/list", p)?;
            models.extend(Model::list(&page));
            cursor = page
                .get("nextCursor")
                .and_then(Value::as_str)
                .map(str::to_string);
            if cursor.is_none() {
                break;
            }
        }
        if let Some(m) = &model
            && !models.iter().any(|x| &x.id == m)
        {
            return Err(AiError::ModelUnavailable(m.clone(), Provider::Codex));
        }
        if let Some(effort) = &settings.effort
            && let Some(found) = model
                .as_ref()
                .and_then(|m| models.iter().find(|x| &x.id == m))
            && !found.efforts.contains(effort)
        {
            return Err(AiError::EffortUnavailable(effort.clone(), found.id.clone()));
        }
    }
    let thread = response
        .get("thread")
        .and_then(|t| t.get("id"))
        .and_then(Value::as_str)
        .ok_or(AiError::CodexInvalidResponse)?
        .to_string();
    let mut turn = json!({
        "threadId": thread,
        "input": [{"type": "text", "text": prompt, "text_elements": []}],
        "outputSchema": strict_schema(schema),
    });
    if let Some(effort) = &settings.effort {
        turn["effort"] = json!(effort);
    }
    rpc.request("turn/start", turn)?;

    let mut stream = EventStream::default();
    let (mut output, mut tokens) = (String::new(), TokenUsage::default());
    loop {
        let Some(msg) = rpc.next_message(deadline)? else {
            return Err(AiError::DiscoverTimedOut);
        };
        let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
        let params = msg.get("params").cloned().unwrap_or(Value::Null);
        if let Some(id) = msg.get("id") {
            // requisição do servidor
            if method == "item/tool/call"
                && params.get("threadId").and_then(Value::as_str) == Some(&thread)
            {
                let tool = params.get("tool").and_then(Value::as_str).unwrap_or("");
                let arguments = params.get("arguments").cloned().unwrap_or(json!({}));
                let result = read_tool_response(root, tool, &arguments);
                rpc.respond(id, result)?;
            } else if method == "item/permissions/requestApproval" {
                rpc.respond(id, json!({"permissions": {}, "scope": "turn"}))?;
            } else if method.contains("requestApproval") {
                rpc.respond(id, json!({"decision": "decline"}))?;
            } else {
                rpc.reject(
                    id,
                    "Esta operação só permite exploração sem interação ou escrita.",
                );
            }
            continue;
        }
        if params.get("threadId").and_then(Value::as_str) != Some(&thread) {
            continue;
        }
        if method == "thread/tokenUsage/updated" {
            tokens = TokenUsage::codex(params.get("tokenUsage").and_then(|t| t.get("total")));
        }
        if let Some(delta) = stream.event(method, &params) {
            output.push_str(&delta);
        }
        if method == "item/completed"
            && params
                .get("item")
                .and_then(|i| i.get("type"))
                .and_then(Value::as_str)
                == Some("agentMessage")
            && params
                .get("item")
                .and_then(|i| i.get("phase"))
                .and_then(Value::as_str)
                == Some("final_answer")
        {
            output = params["item"]
                .get("text")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or(output);
        }
        if method == "turn/completed" {
            let turn = params.get("turn");
            let status = turn.and_then(|t| t.get("status")).and_then(Value::as_str);
            if status == Some("completed") {
                return Ok(ReadOnlyOutput {
                    text: output,
                    tokens,
                    model,
                });
            }
            let message = turn
                .and_then(|t| t.get("error"))
                .and_then(|e| e.get("message"))
                .and_then(Value::as_str)
                .unwrap_or("Exploração interrompida");
            return Err(AiError::CodexServer(message.to_string()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("Sources")).unwrap();
        fs::write(
            dir.path().join("Sources/file.swift"),
            "primeira\nagulha $(touch /tmp/never-execute)\nterceira\n",
        )
        .unwrap();
        dir
    }

    #[test]
    fn le_e_busca_sem_comandos_nem_alteracoes() {
        let dir = fixture();
        let root = dir.path();
        let original = fs::read(root.join("Sources/file.swift")).unwrap();
        let read = execute_read_tool(
            root,
            "Read",
            &json!({"path": "Sources/file.swift", "offset": 2, "limit": 1}),
        )
        .unwrap();
        assert_eq!(
            read,
            "Sources/file.swift:2:agulha $(touch /tmp/never-execute)"
        );
        let grep = execute_read_tool(
            root,
            "Grep",
            &json!({"pattern": "$(touch /tmp/never-execute)", "glob": "Sources/*.swift"}),
        )
        .unwrap();
        assert_eq!(grep, read);
        let glob = execute_read_tool(root, "Glob", &json!({"pattern": "**/*.swift"})).unwrap();
        assert!(glob.contains("Sources/file.swift"));
        assert_eq!(fs::read(root.join("Sources/file.swift")).unwrap(), original);
        let names: Vec<_> = fs::read_dir(root).unwrap().flatten().collect();
        assert_eq!(names.len(), 1);
    }

    #[test]
    fn documentos_do_projeto_continuam_legiveis() {
        let dir = fixture();
        let root = dir.path();
        fs::create_dir_all(root.join(".vibedeck/docs")).unwrap();
        fs::write(
            root.join(".vibedeck/docs/existing.md"),
            "# Documento existente",
        )
        .unwrap();
        let read = execute_read_tool(root, "Read", &json!({"path": ".vibedeck/docs/existing.md"}))
            .unwrap();
        assert!(read.contains("# Documento existente"));
        let glob =
            execute_read_tool(root, "Glob", &json!({"pattern": ".vibedeck/docs/*.md"})).unwrap();
        assert!(glob.contains(".vibedeck/docs/existing.md"));
        let grep = execute_read_tool(
            root,
            "Grep",
            &json!({"pattern": "existente", "glob": ".vibedeck/docs/**"}),
        )
        .unwrap();
        assert!(grep.contains(".vibedeck/docs/existing.md:1:"));
    }

    #[test]
    fn rejeita_fora_symlinks_comandos_e_offsets_invalidos() {
        let dir = fixture();
        let root = dir.path();
        let outside = tempfile::NamedTempFile::new().unwrap();
        fs::write(outside.path(), "outside").unwrap();
        std::os::unix::fs::symlink(outside.path(), root.join("escape.txt")).unwrap();
        let rel = format!(
            "../{}",
            outside.path().file_name().unwrap().to_string_lossy()
        );
        for path in [
            outside.path().to_string_lossy().into_owned(),
            rel,
            "escape.txt".into(),
        ] {
            let r = read_tool_response(root, "Read", &json!({"path": path}));
            assert_eq!(r["success"], false, "{path}");
        }
        for tool in ["Bash", "exec_command", "Write", "Edit"] {
            assert_eq!(read_tool_response(root, tool, &json!({}))["success"], false);
        }
        for offset in [json!(-1.0), json!(0.0), json!(1.5), json!(1e30)] {
            let r = read_tool_response(
                root,
                "Read",
                &json!({"path": "Sources/file.swift", "offset": offset}),
            );
            assert_eq!(r["success"], false, "{offset}");
        }
        assert_eq!(fs::read_to_string(outside.path()).unwrap(), "outside");
    }

    #[test]
    fn saida_limitada_e_glob_pagina() {
        let dir = fixture();
        let root = dir.path();
        fs::write(root.join("long.txt"), "a".repeat(20_000)).unwrap();
        let r = read_tool_response(root, "Read", &json!({"path": "long.txt"}));
        assert_eq!(r["success"], true);
        assert_eq!(
            r["contentItems"][0]["text"]
                .as_str()
                .unwrap()
                .chars()
                .count(),
            16_000
        );
        let first = execute_read_tool(root, "Glob", &json!({"pattern": "**", "limit": 1})).unwrap();
        let second = execute_read_tool(
            root,
            "Glob",
            &json!({"pattern": "**", "offset": 2, "limit": 1}),
        )
        .unwrap();
        assert_ne!(first.lines().next(), second.lines().next());
    }

    #[test]
    fn somente_leitura_desliga_shell_e_mcp_externos() {
        let config = json!({"config": {"mcp_servers": {"external": {"enabled": true}}}});
        let o = read_only_overrides(&config);
        assert_eq!(o["features.shell_tool"], false);
        assert_eq!(o["features.unified_exec"], false);
        assert_eq!(o["mcp_servers.external.enabled"], false);
        let specs = read_tool_specs();
        let names: Vec<&str> = specs
            .as_array()
            .unwrap()
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, ["Read", "Glob", "Grep"]);
    }

    #[test]
    fn schema_estrito_e_glob() {
        let s = strict_schema(
            &json!({"type": "object", "properties": {"a": {"type": "object", "properties": {}}}}),
        );
        assert_eq!(s["additionalProperties"], false);
        assert_eq!(s["properties"]["a"]["additionalProperties"], false);
        assert!(glob_matches("*.rs", "src/a.rs"));
        assert!(glob_matches("src/**", "src/a/b.rs"));
        assert!(!glob_matches("src/*", "src/a/b.rs"));
        assert!(glob_matches("**/a?.rs", "x/ab.rs"));
        assert!(!glob_matches("", "a"));
    }

    #[test]
    fn limites_e_modelos() {
        let limits = RateLimit::list(
            &json!({"rateLimits": {"primary": {"usedPercent": 30, "windowDurationMins": 300, "resetsAt": 1000}}}),
        );
        assert_eq!(limits[0].used_percent, 30.0);
        assert_eq!(limits[0].resets_at, Some(1000.0));
        assert_eq!(limits[0].line(), "codex · primary: 30% · 300 min");
        assert!(RateLimit::list(&Value::Null).is_empty());
        let models = Model::list(&json!({"data": [
            {"model": "m1", "displayName": "M1", "supportedReasoningEfforts": [{"reasoningEffort": "high"}], "isDefault": true},
            {"model": "hid", "hidden": true}]}));
        assert_eq!(models.len(), 1);
        assert_eq!(models[0].efforts, ["high"]);
    }

    #[test]
    fn fluxo_de_eventos_nao_duplica_texto() {
        let mut s = EventStream::default();
        let delta = |id: &str, t: &str| json!({"itemId": id, "delta": t});
        let done =
            |id: &str, t: &str| json!({"item": {"id": id, "type": "agentMessage", "text": t}});
        assert_eq!(
            s.event("item/agentMessage/delta", &delta("a", "Olá")),
            Some("Olá".into())
        );
        assert_eq!(s.event("item/completed", &done("a", "Olá")), None);
        assert_eq!(
            s.event("item/completed", &done("b", "Resposta final")),
            Some("Resposta final".into())
        );
        assert_eq!(
            s.event("item/completed", &done("b", "Resposta final")),
            None
        );
        assert_eq!(
            s.event("item/agentMessage/delta", &delta("b", "atrasado")),
            None
        );
    }
}
