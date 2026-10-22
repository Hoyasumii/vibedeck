//! Logs do VibeDeck: JSON Lines, um arquivo por dia (UTC), FORA dos projetos.
//!
//! Só nomes, ids, tamanhos e códigos entram aqui, nunca conteúdo de prompts/docs/ideias/argumentos.
//!
//! Pasta dos logs (divergência registrada em relação ao Swift, que só roda no macOS):
//! - `VIBEDECK_LOG_DIR`, se definida (testes e instalações especiais);
//! - macOS: `~/Library/Application Support/VibeDeck/logs` (a mesma do app Swift);
//! - Linux e demais: `$XDG_STATE_HOME/vibedeck/logs` ou `~/.local/state/vibedeck/logs`.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::{DateTime, Duration, TimeZone, Utc};
use serde_json::{Map, Value};

use super::{ProjectError, Result};
use crate::json;
use crate::slug;
use crate::time;

// ---- entrada -----------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
    Crash,
}

impl LogLevel {
    pub const ALL: [LogLevel; 5] = [
        LogLevel::Debug,
        LogLevel::Info,
        LogLevel::Warning,
        LogLevel::Error,
        LogLevel::Crash,
    ];

    pub fn raw(self) -> &'static str {
        match self {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warning => "warning",
            LogLevel::Error => "error",
            LogLevel::Crash => "crash",
        }
    }

    pub fn parse(text: &str) -> Option<LogLevel> {
        Self::ALL.into_iter().find(|l| l.raw() == text)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum LogComponent {
    App,
    Cli,
    Mcp,
    Core,
    Rules,
    Ai,
    Hook,
}

impl LogComponent {
    pub const ALL: [LogComponent; 7] = [
        LogComponent::App,
        LogComponent::Cli,
        LogComponent::Mcp,
        LogComponent::Core,
        LogComponent::Rules,
        LogComponent::Ai,
        LogComponent::Hook,
    ];

    pub fn raw(self) -> &'static str {
        match self {
            LogComponent::App => "app",
            LogComponent::Cli => "cli",
            LogComponent::Mcp => "mcp",
            LogComponent::Core => "core",
            LogComponent::Rules => "rules",
            LogComponent::Ai => "ai",
            LogComponent::Hook => "hook",
        }
    }

    pub fn parse(text: &str) -> Option<LogComponent> {
        Self::ALL.into_iter().find(|c| c.raw() == text)
    }
}

pub const MAX_FIELD: usize = 500;
pub const MAX_CONTEXT: usize = 20;
pub const MAX_STACK: usize = 16_000;

#[derive(Debug, Clone, PartialEq)]
pub struct LogEntry {
    pub ts: DateTime<Utc>,
    pub level: LogLevel,
    pub component: LogComponent,
    pub event: String,
    pub message: String,
    pub project: Option<String>,
    pub session: Option<String>,
    pub pid: Option<i32>,
    pub version: Option<String>,
    pub context: BTreeMap<String, String>,
}

fn clip(text: &str, limit: usize) -> String {
    if text.chars().count() > limit {
        let mut s: String = text.chars().take(limit).collect();
        s.push('…');
        s
    } else {
        text.to_string()
    }
}

/// No máximo `MAX_CONTEXT` chaves (ordenadas); chaves e valores truncados (`stack` até `MAX_STACK`).
pub fn sanitized(context: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    context
        .iter()
        .take(MAX_CONTEXT)
        .map(|(k, v)| {
            (
                clip(k, 60),
                clip(v, if k == "stack" { MAX_STACK } else { MAX_FIELD }),
            )
        })
        .collect()
}

/// ISO-8601 UTC com milissegundos (várias entradas por segundo mantêm a ordem).
pub fn stamp(ts: DateTime<Utc>) -> String {
    time::format_iso_millis(ts)
}

impl LogEntry {
    pub fn new(
        level: LogLevel,
        component: LogComponent,
        event: &str,
        message: &str,
        context: BTreeMap<String, String>,
    ) -> LogEntry {
        LogEntry {
            ts: time::now(),
            level,
            component,
            event: clip(event, 80),
            message: clip(message, MAX_FIELD),
            project: None,
            session: None,
            pid: None,
            version: None,
            context: sanitized(&context),
        }
    }

    pub fn action(&self) -> Option<&str> {
        self.context.get("action").map(String::as_str)
    }

    /// Uma linha legível (CLI e relatório).
    pub fn line(&self) -> String {
        let extra = self
            .context
            .iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join(" ");
        format!(
            "{} [{}] {} {}: {}{}",
            stamp(self.ts),
            self.level.raw(),
            self.component.raw(),
            self.event,
            self.message,
            if extra.is_empty() {
                String::new()
            } else {
                format!("  {{{extra}}}")
            }
        )
    }

    pub fn to_json(&self) -> Value {
        let mut o = Map::new();
        o.insert("ts".into(), Value::String(stamp(self.ts)));
        o.insert("level".into(), Value::String(self.level.raw().into()));
        o.insert(
            "component".into(),
            Value::String(self.component.raw().into()),
        );
        o.insert("event".into(), Value::String(self.event.clone()));
        o.insert("message".into(), Value::String(self.message.clone()));
        if let Some(p) = &self.project {
            o.insert("project".into(), Value::String(p.clone()));
        }
        if let Some(s) = &self.session {
            o.insert("session".into(), Value::String(s.clone()));
        }
        if let Some(p) = self.pid {
            o.insert("pid".into(), Value::from(p));
        }
        if let Some(v) = &self.version {
            o.insert("version".into(), Value::String(v.clone()));
        }
        if !self.context.is_empty() {
            let c: Map<String, Value> = self
                .context
                .iter()
                .map(|(k, v)| (k.clone(), Value::String(v.clone())))
                .collect();
            o.insert("context".into(), Value::Object(c));
        }
        Value::Object(o)
    }

    /// Leitura tolerante, como o `init(from:)` do Swift: `None` = linha inutilizável (ignorada).
    pub fn from_json(value: &Value) -> Option<LogEntry> {
        let o = value.as_object()?;
        let opt_string = |key: &str| -> Option<Option<String>> {
            match o.get(key) {
                None | Some(Value::Null) => Some(None),
                Some(Value::String(s)) => Some(Some(s.clone())),
                Some(_) => None,
            }
        };
        let ts = match o.get("ts") {
            None | Some(Value::Null) => Utc.with_ymd_and_hms(1, 1, 1, 0, 0, 0).single()?,
            Some(Value::String(s)) => time::parse_iso(s)?,
            Some(_) => return None,
        };
        let level = o
            .get("level")
            .and_then(Value::as_str)
            .and_then(LogLevel::parse)
            .unwrap_or(LogLevel::Info);
        let component = o
            .get("component")
            .and_then(Value::as_str)
            .and_then(LogComponent::parse)
            .unwrap_or(LogComponent::Core);
        let pid = match o.get("pid") {
            None | Some(Value::Null) => None,
            Some(Value::Number(n)) => Some(i32::try_from(n.as_i64()?).ok()?),
            Some(_) => return None,
        };
        let context = match o.get("context") {
            Some(Value::Object(c)) if c.values().all(Value::is_string) => sanitized(
                &c.iter()
                    .map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string()))
                    .collect(),
            ),
            _ => BTreeMap::new(),
        };
        Some(LogEntry {
            ts,
            level,
            component,
            event: opt_string("event")?.unwrap_or_default(),
            message: opt_string("message")?.unwrap_or_default(),
            project: opt_string("project")?,
            session: opt_string("session")?,
            pid,
            version: opt_string("version")?,
            context,
        })
    }
}

impl serde::Serialize for LogEntry {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        self.to_json().serialize(s)
    }
}

// ---- filtro ------------------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct LogFilter {
    pub since: Option<DateTime<Utc>>,
    pub min_level: LogLevel,
    /// Vazio = todos.
    pub components: Vec<LogComponent>,
    /// Raiz do projeto; com `Some`, entradas sem projeto não passam.
    pub project: Option<String>,
    pub search: Option<String>,
    pub action: Option<String>,
    pub limit: i64,
}

impl Default for LogFilter {
    fn default() -> Self {
        LogFilter {
            since: None,
            min_level: LogLevel::Debug,
            components: Vec::new(),
            project: None,
            search: None,
            action: None,
            limit: 200,
        }
    }
}

fn trim_blank(s: &str) -> &str {
    s.trim_matches([' ', '\t'])
}

impl LogFilter {
    pub fn matches(&self, entry: &LogEntry) -> bool {
        if let Some(action) = &self.action
            && entry.action() != Some(action.as_str())
        {
            return false;
        }
        if let Some(since) = self.since
            && entry.ts < since
        {
            return false;
        }
        if entry.level < self.min_level {
            return false;
        }
        if !self.components.is_empty() && !self.components.contains(&entry.component) {
            return false;
        }
        if let Some(project) = &self.project
            && entry.project.as_deref() != Some(project.as_str())
        {
            return false;
        }
        if let Some(search) = &self.search {
            let needle = trim_blank(search);
            if !needle.is_empty() {
                let mut parts = vec![entry.event.as_str(), entry.message.as_str()];
                parts.extend(entry.context.values().map(String::as_str));
                if !slug::fold(&parts.join(" ")).contains(&slug::fold(needle)) {
                    return false;
                }
            }
        }
        true
    }

    /// `30m`, `24h`, `7d` (ou um número puro de horas) antes de `now`.
    pub fn parse_since(text: &str, now: DateTime<Utc>) -> Result<DateTime<Utc>> {
        let bad = || ProjectError::InvalidLogFilter(text.to_string());
        let t = trim_blank(text).to_lowercase();
        let unit = t.chars().last().filter(|c| c.is_alphabetic());
        let number = match unit {
            Some(u) => &t[..t.len() - u.len_utf8()],
            None => t.as_str(),
        };
        let n: f64 = number.parse().map_err(|_| bad())?;
        if n.is_nan() || n < 0.0 {
            return Err(bad());
        }
        let per = match unit {
            Some('m') => 60.0,
            Some('h') | None => 3600.0,
            Some('d') => 86400.0,
            Some(_) => return Err(bad()),
        };
        let millis = (n * per * 1000.0).min(i64::MAX as f64 / 2.0) as i64;
        Ok(now
            .checked_sub_signed(Duration::milliseconds(millis))
            .unwrap_or(DateTime::<Utc>::MIN_UTC))
    }

    pub fn parse_level(text: &str) -> Result<LogLevel> {
        LogLevel::parse(&text.to_lowercase())
            .ok_or_else(|| ProjectError::InvalidLogFilter(text.to_string()))
    }

    pub fn parse_components(values: &[String]) -> Result<Vec<LogComponent>> {
        let mut out = Vec::new();
        for v in values {
            let c = LogComponent::parse(&v.to_lowercase())
                .ok_or_else(|| ProjectError::InvalidLogFilter(v.clone()))?;
            if !out.contains(&c) {
                out.push(c);
            }
        }
        Ok(out)
    }
}

// ---- armazém -----------------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct LogStore {
    pub dir: PathBuf,
    /// Passado deste tamanho, o dia só aceita aviso, erro e crash.
    pub max_daily_bytes: u64,
}

pub const MAX_AGE_DAYS: i64 = 14;

impl LogStore {
    pub fn new(dir: impl Into<PathBuf>) -> LogStore {
        LogStore {
            dir: dir.into(),
            max_daily_bytes: 5_000_000,
        }
    }

    /// Veja a documentação do módulo para a escolha da pasta.
    pub fn default_dir() -> PathBuf {
        if let Some(dir) = std::env::var_os("VIBEDECK_LOG_DIR").filter(|d| !d.is_empty()) {
            return PathBuf::from(dir);
        }
        let home = || {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_default()
        };
        if cfg!(target_os = "macos") {
            return home().join("Library/Application Support/VibeDeck/logs");
        }
        match std::env::var_os("XDG_STATE_HOME").filter(|d| !d.is_empty()) {
            Some(state) => PathBuf::from(state).join("vibedeck/logs"),
            None => home().join(".local/state/vibedeck/logs"),
        }
    }

    pub fn default_store() -> LogStore {
        LogStore::new(Self::default_dir())
    }

    pub fn day(ts: DateTime<Utc>) -> String {
        ts.format("%Y-%m-%d").to_string()
    }

    pub fn file_for(&self, ts: DateTime<Utc>) -> PathBuf {
        self.dir.join(format!("{}.jsonl", Self::day(ts)))
    }

    /// Arquivos de dia, o mais novo primeiro.
    fn files(&self) -> Vec<PathBuf> {
        let Ok(rd) = fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut files: Vec<PathBuf> = rd
            .filter_map(|e| e.ok())
            .filter(|e| !e.file_name().to_string_lossy().starts_with('.'))
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "jsonl"))
            .collect();
        files.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
        files
    }

    /// Acrescenta a linha com uma única escrita em modo append (processos concorrentes não se misturam).
    pub fn append(&self, entry: &LogEntry) -> Result<()> {
        let mut data = json::to_compact(&entry.to_json()).into_bytes();
        data.push(b'\n');
        let path = self.file_for(entry.ts);
        let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        if size >= self.max_daily_bytes && entry.level < LogLevel::Warning {
            return Ok(());
        }
        fs::create_dir_all(&self.dir).map_err(|e| ProjectError::LogUnavailable(e.to_string()))?;
        let mut options = fs::OpenOptions::new();
        options.append(true).create(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o644);
        }
        let mut file = options
            .open(&path)
            .map_err(|e| ProjectError::LogUnavailable(e.to_string()))?;
        file.write_all(&data)
            .map_err(|e| ProjectError::LogUnavailable(e.to_string()))
    }

    /// Entradas que casam, mais novas primeiro. Linhas ilegíveis são ignoradas.
    pub fn entries(&self, filter: &LogFilter) -> Vec<LogEntry> {
        let first_day = filter.since.map(Self::day);
        let mut out = Vec::new();
        for file in self.files() {
            let stem = file
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            if let Some(first) = &first_day
                && stem < *first
            {
                break;
            }
            let Ok(data) = fs::read(&file) else { continue };
            let mut decoded: Vec<LogEntry> = data
                .split(|b| *b == b'\n')
                .filter(|l| !l.is_empty())
                .filter_map(|l| serde_json::from_slice::<Value>(l).ok())
                .filter_map(|v| LogEntry::from_json(&v))
                .collect();
            // Um dia pode ter linhas de vários processos levemente fora de ordem.
            decoded.sort_by_key(|e| std::cmp::Reverse(e.ts));
            for entry in decoded {
                if filter.matches(&entry) {
                    out.push(entry);
                    if out.len() as i64 >= filter.limit {
                        return out;
                    }
                }
            }
        }
        out
    }

    /// Remove os dias com mais de `MAX_AGE_DAYS`. Devolve quantos arquivos saíram.
    pub fn prune(&self, now: DateTime<Utc>) -> usize {
        let cutoff = Self::day(now - Duration::days(MAX_AGE_DAYS));
        let mut removed = 0;
        for file in self.files() {
            let stem = file
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            if stem < cutoff && fs::remove_file(&file).is_ok() {
                removed += 1;
            }
        }
        removed
    }

    /// Relatório em texto (mais antigo primeiro) para colar numa issue.
    pub fn report(&self, filter: &LogFilter, header: Option<&str>) -> String {
        let entries = self.entries(filter);
        let mut lines = vec![
            header
                .unwrap_or("Relatório de diagnóstico do VibeDeck")
                .to_string(),
            format!("Gerado em {}", time::format_iso(time::now())),
            format!("Entradas: {}", entries.len()),
            String::new(),
        ];
        lines.extend(entries.iter().rev().map(LogEntry::line));
        lines.join("\n") + "\n"
    }
}

/// Filtro padrão do relatório: aviso ou pior.
pub fn report_filter() -> LogFilter {
    LogFilter {
        min_level: LogLevel::Warning,
        ..LogFilter::default()
    }
}

// ---- fachada de escrita ------------------------------------------------------------------------

struct Config {
    component: LogComponent,
    store: Option<LogStore>,
    version: Option<String>,
    project: Option<String>,
    session: String,
}

static STATE: Mutex<Option<Config>> = Mutex::new(None);

fn state() -> std::sync::MutexGuard<'static, Option<Config>> {
    STATE.lock().unwrap_or_else(|e| e.into_inner())
}

/// Liga o log deste processo. Processos não configurados (testes, bibliotecas) nunca gravam.
pub fn configure(component: LogComponent, version: Option<&str>, store: Option<LogStore>) {
    let mut s = state();
    let project = s.as_ref().and_then(|c| c.project.clone());
    let session = s
        .as_ref()
        .map(|c| c.session.clone())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string().to_uppercase());
    *s = Some(Config {
        component,
        store,
        version: version.map(str::to_string),
        project,
        session,
    });
}

/// Projeto padrão das entradas que não nomeiam um (a raiz do CLI/MCP).
pub fn set_project(root: Option<&Path>) {
    if let Some(c) = state().as_mut() {
        c.project = root.map(|r| r.to_string_lossy().into_owned());
    }
}

/// Grava uma entrada (síncrono). Falhas vão para o stderr; nunca interrompem quem chama.
pub fn log(level: LogLevel, event: &str, message: &str, context: &[(&str, &str)]) {
    let (store, mut entry) = {
        let s = state();
        let Some(c) = s.as_ref() else { return };
        let Some(store) = c.store.clone() else { return };
        let mut ctx: BTreeMap<String, String> = context
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        if let Some(action) = std::env::var("VIBEDECK_ACTION")
            .ok()
            .filter(|a| !a.is_empty())
        {
            ctx.insert("action".into(), action);
        }
        let mut entry = LogEntry::new(level, c.component, event, message, ctx);
        entry.project = c.project.clone();
        entry.session = Some(c.session.clone());
        entry.version = c.version.clone();
        (store, entry)
    };
    entry.pid = Some(std::process::id() as i32);
    if let Err(e) = store.append(&entry) {
        eprintln!("{e}");
    }
}

pub fn info(event: &str, message: &str, context: &[(&str, &str)]) {
    log(LogLevel::Info, event, message, context);
}

pub fn warning(event: &str, message: &str, context: &[(&str, &str)]) {
    log(LogLevel::Warning, event, message, context);
}

pub fn error(event: &str, message: &str, context: &[(&str, &str)]) {
    log(LogLevel::Error, event, message, context);
}

// ---- consultas compartilhadas por CLI e MCP ------------------------------------------------------

/// `read_logs` (MCP): padrões since=24h, level=info, limite 200 limitado a 1..=2000, projeto = raiz.
pub fn read_logs(
    store: &LogStore,
    root: &Path,
    since: Option<&str>,
    level: Option<&str>,
    components: &[String],
    action: Option<&str>,
    limit: Option<i64>,
) -> Result<Vec<LogEntry>> {
    let filter = LogFilter {
        since: Some(LogFilter::parse_since(since.unwrap_or("24h"), time::now())?),
        min_level: LogFilter::parse_level(level.unwrap_or("info"))?,
        components: LogFilter::parse_components(components)?,
        project: Some(root.to_string_lossy().into_owned()),
        search: None,
        action: action.map(str::to_string),
        limit: limit.unwrap_or(200).clamp(1, 2000),
    };
    Ok(store.entries(&filter))
}

/// Recurso `vibedeck://logs`: 24h, aviso ou pior, projeto atual, 50 entradas.
pub fn resource_logs(store: &LogStore, root: &Path) -> Result<Vec<LogEntry>> {
    let filter = LogFilter {
        since: Some(LogFilter::parse_since("24h", time::now())?),
        min_level: LogLevel::Warning,
        project: Some(root.to_string_lossy().into_owned()),
        limit: 50,
        ..LogFilter::default()
    };
    Ok(store.entries(&filter))
}

/// Recurso `vibedeck://logs/crashes`: 14 dias, só crash, qualquer projeto, 50 entradas.
pub fn resource_crashes(store: &LogStore) -> Result<Vec<LogEntry>> {
    let filter = LogFilter {
        since: Some(LogFilter::parse_since("14d", time::now())?),
        min_level: LogLevel::Crash,
        limit: 50,
        ..LogFilter::default()
    };
    Ok(store.entries(&filter))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(level: LogLevel, event: &str, ts: DateTime<Utc>) -> LogEntry {
        let mut e = LogEntry::new(
            level,
            LogComponent::Cli,
            event,
            &format!("mensagem {event}"),
            BTreeMap::new(),
        );
        e.ts = ts;
        e
    }

    #[test]
    fn anexa_e_filtra_mais_novo_primeiro() {
        let tmp = tempfile::tempdir().unwrap();
        let logs = LogStore::new(tmp.path());
        let now = time::now();
        let mut a = entry(LogLevel::Info, "a", now - Duration::seconds(30));
        a.project = Some("/p1".into());
        let mut b = entry(LogLevel::Error, "b", now - Duration::seconds(20));
        b.component = LogComponent::Mcp;
        b.project = Some("/p1".into());
        let mut c = entry(LogLevel::Warning, "c", now - Duration::seconds(10));
        c.project = Some("/p2".into());
        for e in [&a, &b, &c] {
            logs.append(e).unwrap();
        }
        let names = |f: &LogFilter| {
            logs.entries(f)
                .into_iter()
                .map(|e| e.event)
                .collect::<Vec<_>>()
        };
        assert_eq!(names(&LogFilter::default()), ["c", "b", "a"]);
        let f = |g: fn(&mut LogFilter)| {
            let mut x = LogFilter::default();
            g(&mut x);
            x
        };
        assert_eq!(names(&f(|x| x.min_level = LogLevel::Warning)), ["c", "b"]);
        assert_eq!(names(&f(|x| x.components = vec![LogComponent::Mcp])), ["b"]);
        assert_eq!(names(&f(|x| x.project = Some("/p1".into()))), ["b", "a"]);
        assert_eq!(names(&f(|x| x.search = Some("MENSAGEM C".into()))), ["c"]);
        assert_eq!(names(&f(|x| x.limit = 1)), ["c"]);
        let since = now - Duration::seconds(15);
        let g = LogFilter {
            since: Some(since),
            ..LogFilter::default()
        };
        assert_eq!(names(&g), ["c"]);
    }

    #[test]
    fn linhas_corrompidas_e_fracao_de_segundos() {
        let tmp = tempfile::tempdir().unwrap();
        let logs = LogStore::new(tmp.path());
        let ts = Utc.timestamp_millis_opt(1_800_000_000_500).unwrap();
        logs.append(&entry(LogLevel::Error, "ok", ts)).unwrap();
        let path = logs.file_for(ts);
        let mut f = fs::OpenOptions::new().append(true).open(&path).unwrap();
        f.write_all("não é json\n{\"level\":\"desconhecido\"}\n".as_bytes())
            .unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains(".500Z"));
        let read = logs.entries(&LogFilter {
            limit: 10,
            ..LogFilter::default()
        });
        assert_eq!(read.len(), 2);
        assert!(
            read.iter()
                .any(|e| e.event.is_empty() && e.level == LogLevel::Info)
        );
        let ok = read.iter().find(|e| e.event == "ok").unwrap();
        assert_eq!(ok.ts, ts);
    }

    #[test]
    fn higieniza_campos_longos() {
        let long = "x".repeat(2000);
        let ctx: BTreeMap<String, String> = (0..30)
            .map(|i| (format!("k{i:02}"), long.clone()))
            .collect();
        let e = LogEntry::new(LogLevel::Error, LogComponent::Core, "e", &long, ctx);
        assert_eq!(e.message.chars().count(), MAX_FIELD + 1);
        assert_eq!(e.context.len(), MAX_CONTEXT);
        assert!(
            e.context
                .values()
                .all(|v| v.chars().count() == MAX_FIELD + 1)
        );
        assert!(e.context.contains_key("k00") && !e.context.contains_key("k29"));
        let stack = "y".repeat(5000);
        let c = BTreeMap::from([
            ("stack".to_string(), stack.clone()),
            ("name".into(), stack.clone()),
        ]);
        let e = LogEntry::new(LogLevel::Crash, LogComponent::App, "e", "m", c);
        assert_eq!(e.context["stack"], stack);
        assert_eq!(e.context["name"].chars().count(), MAX_FIELD + 1);
    }

    #[test]
    fn campos_opcionais_vazios_ficam_de_fora() {
        let e = LogEntry::new(LogLevel::Info, LogComponent::App, "e", "m", BTreeMap::new());
        let v = e.to_json();
        let mut keys: Vec<&String> = v.as_object().unwrap().keys().collect();
        keys.sort();
        assert_eq!(keys, ["component", "event", "level", "message", "ts"]);
    }

    #[test]
    fn poda_dias_antigos_e_limita_tamanho_diario() {
        let tmp = tempfile::tempdir().unwrap();
        let mut logs = LogStore::new(tmp.path());
        logs.max_daily_bytes = 400;
        let now = time::now();
        logs.append(&entry(LogLevel::Error, "velho", now - Duration::days(20)))
            .unwrap();
        for i in 0..10 {
            logs.append(&entry(LogLevel::Info, &format!("info{i}"), now))
                .unwrap();
        }
        logs.append(&entry(LogLevel::Error, "erro", now)).unwrap();
        let today = logs.entries(&LogFilter {
            since: Some(now - Duration::seconds(60)),
            limit: 100,
            ..LogFilter::default()
        });
        assert!(today.len() < 11);
        assert!(today.iter().any(|e| e.event == "erro"));
        assert_eq!(logs.prune(now), 1);
        assert!(
            !logs
                .entries(&LogFilter {
                    limit: 100,
                    ..LogFilter::default()
                })
                .iter()
                .any(|e| e.event == "velho")
        );
    }

    #[test]
    fn filtros_de_texto() {
        let now = Utc.timestamp_opt(1_000_000, 0).unwrap();
        let s = |t| LogFilter::parse_since(t, now).unwrap();
        assert_eq!(s("30m"), now - Duration::seconds(1800));
        assert_eq!(s("24h"), now - Duration::seconds(86400));
        assert_eq!(s("2"), now - Duration::seconds(7200));
        assert_eq!(s("7d"), now - Duration::seconds(7 * 86400));
        assert_eq!(
            LogFilter::parse_since("1w", now).unwrap_err().to_string(),
            "Filtro de log inválido: 1w. Use, por exemplo, 30m, 24h ou 7d."
        );
        assert!(LogFilter::parse_since("-1h", now).is_err());
        assert!(LogFilter::parse_since("", now).is_err());
        assert!(LogFilter::parse_level("fatal").is_err());
        assert_eq!(
            LogFilter::parse_components(&["MCP".into(), "app".into()]).unwrap(),
            [LogComponent::Mcp, LogComponent::App]
        );
    }

    #[test]
    fn relatorio_cronologico() {
        let tmp = tempfile::tempdir().unwrap();
        let logs = LogStore::new(tmp.path());
        let now = time::now();
        logs.append(&entry(
            LogLevel::Error,
            "primeiro",
            now - Duration::seconds(2),
        ))
        .unwrap();
        logs.append(&entry(
            LogLevel::Warning,
            "segundo",
            now - Duration::seconds(1),
        ))
        .unwrap();
        logs.append(&entry(LogLevel::Info, "ignorado", now))
            .unwrap();
        let report = logs.report(&report_filter(), Some("Teste"));
        assert!(report.starts_with("Teste\n"));
        assert!(report.contains("Entradas: 2"));
        assert!(report.find("primeiro").unwrap() < report.find("segundo").unwrap());
        assert!(!report.contains("ignorado"));
    }

    #[test]
    fn filtro_de_acao_e_leitura_antiga() {
        let tmp = tempfile::tempdir().unwrap();
        let logs = LogStore::new(tmp.path());
        for (action, event) in [
            ("a1", "ui.activated"),
            ("a1", "store.file_written"),
            ("a2", "ui.activated"),
        ] {
            let ctx = BTreeMap::from([("action".to_string(), action.to_string())]);
            logs.append(&LogEntry::new(
                LogLevel::Info,
                LogComponent::App,
                event,
                "Operação",
                ctx,
            ))
            .unwrap();
        }
        let only = |a: &str| {
            logs.entries(&LogFilter {
                action: Some(a.into()),
                ..LogFilter::default()
            })
        };
        assert_eq!(only("a1").len(), 2);
        assert!(only("missing").is_empty());
        let old =
            LogEntry::from_json(&serde_json::json!({"event":"legacy","context":null})).unwrap();
        assert!(old.action().is_none());
        let unknown =
            LogEntry::from_json(&serde_json::json!({"level":"future","context":{"action":42}}))
                .unwrap();
        assert_eq!(unknown.level, LogLevel::Info);
        assert!(unknown.context.is_empty());
    }

    #[test]
    fn appends_concorrentes_mantem_linhas_inteiras() {
        let tmp = tempfile::tempdir().unwrap();
        let logs = LogStore::new(tmp.path());
        std::thread::scope(|s| {
            for i in 0..50 {
                let logs = logs.clone();
                s.spawn(move || {
                    let e = LogEntry::new(
                        LogLevel::Error,
                        LogComponent::Mcp,
                        &format!("e{i}"),
                        &"m".repeat(300),
                        BTreeMap::new(),
                    );
                    logs.append(&e).unwrap();
                });
            }
        });
        let all = logs.entries(&LogFilter {
            limit: 1000,
            ..LogFilter::default()
        });
        assert_eq!(all.len(), 50);
    }
}
