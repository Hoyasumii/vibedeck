//! Consumo de IA: métricas locais por tarefa (`AIUsage.swift`) e limites do plano do Claude Code lidos da
//! statusline (`ClaudeUsage.swift`). Ambos ficam fora do projeto: são da máquina, não do repositório.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, TimeZone, Utc};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Map, Value, json};

use super::{AiError, Provider, Result, home_dir, local_store_dir, machine_dir};
use crate::json;
use crate::model::{Id, Timestamp};
use crate::store::write_atomic;

/// `Double` do Swift: inteiros saem sem `.0` (`0`, `18`), o resto como `f64`.
fn ser_num<S: Serializer>(v: &f64, s: S) -> std::result::Result<S::Ok, S::Error> {
    if v.is_finite() && v.fract() == 0.0 && v.abs() < 9e15 {
        s.serialize_i64(*v as i64)
    } else {
        s.serialize_f64(*v)
    }
}

fn ser_opt_num<S: Serializer>(v: &Option<f64>, s: S) -> std::result::Result<S::Ok, S::Error> {
    match v {
        Some(v) => ser_num(v, s),
        None => s.serialize_none(),
    }
}

fn de_default<'de, D: Deserializer<'de>, T: Deserialize<'de> + Default>(
    d: D,
) -> std::result::Result<T, D::Error> {
    Ok(Option::<T>::deserialize(d)?.unwrap_or_default())
}

// ---- tokens ----------------------------------------------------------------------------------------

/// Contagens informadas pelo provider; `None` = indisponível, nunca zero nem estimativa por caracteres.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenUsage {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cached_input: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_output: Option<i64>,
}

fn count(value: Option<&Value>) -> Option<i64> {
    let n = value?.as_f64()?;
    (n.is_finite() && n >= 0.0 && n < i64::MAX as f64 && n.floor() == n).then_some(n as i64)
}

impl TokenUsage {
    /// O Claude informa as categorias de cache separadas da entrada sem cache.
    pub fn claude(value: Option<&Value>) -> Self {
        let get = |k: &str| count(value.and_then(|v| v.get(k)));
        let (uncached, cached, write) = (
            get("input_tokens"),
            get("cache_read_input_tokens"),
            get("cache_creation_input_tokens"),
        );
        TokenUsage {
            input: uncached.map(|u| u + cached.unwrap_or(0) + write.unwrap_or(0)),
            output: get("output_tokens"),
            cached_input: cached,
            cache_write: write,
            reasoning_output: None,
        }
    }

    pub fn codex(value: Option<&Value>) -> Self {
        let get = |k: &str| count(value.and_then(|v| v.get(k)));
        TokenUsage {
            input: get("inputTokens"),
            output: get("outputTokens"),
            cached_input: get("cachedInputTokens"),
            cache_write: get("cacheWriteInputTokens"),
            reasoning_output: get("reasoningOutputTokens"),
        }
    }

    /// Totais cumulativos do Codex → este turno. Nunca some eventos cumulativos.
    pub fn since(&self, baseline: &TokenUsage) -> TokenUsage {
        let delta = |a: Option<i64>, b: Option<i64>| a.map(|a| (a - b.unwrap_or(0)).max(0));
        TokenUsage {
            input: delta(self.input, baseline.input),
            output: delta(self.output, baseline.output),
            cached_input: delta(self.cached_input, baseline.cached_input),
            cache_write: delta(self.cache_write, baseline.cache_write),
            reasoning_output: delta(self.reasoning_output, baseline.reasoning_output),
        }
    }
}

// ---- registros -------------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageRecord {
    #[serde(default)]
    pub id: Id,
    #[serde(rename = "taskID")]
    pub task_id: String,
    pub operation: String,
    pub provider: Provider,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default)]
    pub started_at: Timestamp,
    #[serde(default, serialize_with = "ser_num", deserialize_with = "de_default")]
    pub duration: f64,
    pub attempt: i64,
    #[serde(default = "running")]
    pub status: String,
    pub prompt_characters: i64,
    #[serde(default)]
    pub tokens: TokenUsage,
    #[serde(
        default,
        rename = "costUSD",
        skip_serializing_if = "Option::is_none",
        serialize_with = "ser_opt_num"
    )]
    pub cost_usd: Option<f64>,
    #[serde(default = "provider_reported")]
    pub coverage: String,
}

fn running() -> String {
    "running".into()
}

fn provider_reported() -> String {
    "provider-reported".into()
}

impl UsageRecord {
    pub fn new(operation: &str, provider: Provider, prompt: &str) -> Self {
        UsageRecord {
            id: Id::new(),
            task_id: uuid_upper(),
            operation: operation.to_string(),
            provider,
            model: None,
            started_at: Timestamp::now(),
            duration: 0.0,
            attempt: 1,
            status: running(),
            prompt_characters: super::graphemes::count(prompt) as i64,
            tokens: TokenUsage::default(),
            cost_usd: None,
            coverage: provider_reported(),
        }
    }

    pub fn finish(&mut self, status: &str) {
        self.status = status.to_string();
        let elapsed = Timestamp::now().0 - self.started_at.0;
        self.duration = (elapsed.num_milliseconds() as f64 / 1000.0).max(0.0);
    }
}

fn uuid_upper() -> String {
    Id::new().to_string()
}

/// Um arquivo por tentativa: evita corrida de leitura/escrita entre jobs e processos.
#[derive(Debug, Clone)]
pub struct UsageStore {
    pub directory: PathBuf,
}

impl UsageStore {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        UsageStore {
            directory: directory.into(),
        }
    }

    pub fn for_root(root: &Path) -> Self {
        UsageStore::new(local_store_dir(root).join("usage"))
    }

    pub fn save(&self, record: &UsageRecord) -> Result<()> {
        let bytes = json::encode(record).map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
        write_atomic(&self.directory.join(format!("{}.json", record.id)), &bytes)?;
        Ok(())
    }

    fn files(&self) -> Vec<PathBuf> {
        let Ok(entries) = fs::read_dir(&self.directory) else {
            return vec![];
        };
        let mut files: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.extension()
                    .is_some_and(|e| e.eq_ignore_ascii_case("json"))
            })
            .collect();
        files.sort();
        files
    }

    /// Mais recente primeiro. Arquivos que não decodificam são ignorados (o Swift falharia a listagem).
    pub fn list(&self) -> Result<Vec<UsageRecord>> {
        let mut records: Vec<UsageRecord> = self
            .files()
            .iter()
            .filter_map(|f| fs::read(f).ok())
            .filter_map(|b| serde_json::from_slice(&b).ok())
            .collect();
        records.sort_by(|a, b| {
            b.started_at
                .cmp(&a.started_at)
                .then_with(|| a.id.cmp(&b.id))
        });
        Ok(records)
    }

    pub fn clear(&self) -> Result<()> {
        for file in self.files() {
            fs::remove_file(&file).map_err(|e| AiError::io(&file, e))?;
        }
        Ok(())
    }
}

/// Linha de `ai usage` (sem `--json`).
pub fn usage_line(r: &UsageRecord) -> String {
    let n = |v: Option<i64>| v.map_or("não informada".to_string(), |v| v.to_string());
    format!(
        "{} · {} · {} · tarefa {} · tentativa {} · entrada {} · saída {} · {}",
        r.operation,
        r.provider.title(),
        r.model.as_deref().unwrap_or("modelo não informado"),
        r.task_id,
        r.attempt,
        n(r.tokens.input),
        n(r.tokens.output),
        r.status
    )
}

// ---- limites do Claude Code (statusline) -----------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    /// 0–100.
    #[serde(serialize_with = "ser_num")]
    pub used_percentage: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resets_at: Option<Timestamp>,
}

impl Window {
    /// Percentual valendo em `now`: depois do reset a janela recomeça do zero.
    pub fn percentage(&self, now: DateTime<Utc>) -> f64 {
        if let Some(reset) = self.resets_at
            && reset.0 <= now
        {
            return 0.0;
        }
        self.used_percentage.clamp(0.0, 100.0)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeUsage {
    /// Janela de 5 horas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<Window>,
    /// 7 dias.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weekly: Option<Window>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default = "distant_past")]
    pub updated_at: Timestamp,
}

fn distant_past() -> Timestamp {
    Timestamp(Utc.with_ymd_and_hms(1, 1, 1, 0, 0, 0).unwrap())
}

fn local_hm(t: DateTime<Utc>) -> String {
    t.with_timezone(&chrono::Local).format("%H:%M").to_string()
}

/// Data abreviada + hora curta, no fuso local (o Swift usa o locale do sistema).
pub fn local_date_time(t: DateTime<Utc>) -> String {
    t.with_timezone(&chrono::Local)
        .format("%d/%m/%Y %H:%M")
        .to_string()
}

impl ClaudeUsage {
    pub fn has_limits(&self) -> bool {
        self.session.is_some() || self.weekly.is_some()
    }

    /// Lê o JSON que o Claude Code manda para a statusline (`rate_limits.five_hour` / `seven_day`, com
    /// `used_percentage` e `resets_at` em segundos Unix).
    pub fn from_status_line(data: &[u8], now: DateTime<Utc>) -> Result<ClaudeUsage> {
        let root: Value = serde_json::from_slice(data).map_err(|_| AiError::InvalidStatusLine)?;
        let Some(root) = root.as_object() else {
            return Err(AiError::InvalidStatusLine);
        };
        let limits = root.get("rate_limits").and_then(Value::as_object);
        let model = root
            .get("model")
            .and_then(|m| m.get("display_name"))
            .and_then(Value::as_str)
            .map(str::to_string);
        Ok(ClaudeUsage {
            session: limits.and_then(|l| l.get("five_hour")).and_then(window),
            weekly: limits.and_then(|l| l.get("seven_day")).and_then(window),
            model,
            updated_at: Timestamp(now),
        })
    }

    /// "sessão 42% (reinicia 14:30) · semana 18%".
    pub fn summary(&self, now: DateTime<Utc>) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(model) = &self.model {
            parts.push(model.clone());
        }
        if let Some(session) = &self.session {
            let mut text = format!("sessão {}%", session.percentage(now).round() as i64);
            if let Some(reset) = session.resets_at
                && reset.0 > now
            {
                text.push_str(&format!(" (reinicia {})", local_hm(reset.0)));
            }
            parts.push(text);
        }
        if let Some(weekly) = &self.weekly {
            parts.push(format!("semana {}%", weekly.percentage(now).round() as i64));
        }
        parts.join(" · ")
    }
}

fn window(value: &Value) -> Option<Window> {
    let dict = value.as_object()?;
    let used = dict.get("used_percentage")?.as_f64()?;
    let reset = match dict.get("resets_at") {
        Some(Value::Number(n)) => n.as_f64().and_then(|secs| {
            let whole = secs.floor();
            DateTime::from_timestamp(whole as i64, ((secs - whole) * 1e9) as u32).map(Timestamp)
        }),
        Some(Value::String(s)) => crate::time::parse_iso(s).map(Timestamp),
        _ => None,
    };
    Some(Window {
        used_percentage: used,
        resets_at: reset,
    })
}

// ---- Claude Code na máquina -------------------------------------------------------------------------

/// Onde `usage record` grava o último uso informado pelo Claude Code.
pub fn usage_path() -> PathBuf {
    machine_dir("claude-usage.json")
}

pub fn settings_path() -> PathBuf {
    home_dir().join(".claude/settings.json")
}

/// Grava o uso da statusline. Sem limites (sessão sem resposta da API, conta sem plano) não apaga o último
/// valor conhecido.
pub fn record_usage(status_line: &[u8], to: &Path, now: DateTime<Utc>) -> Result<ClaudeUsage> {
    let usage = ClaudeUsage::from_status_line(status_line, now)?;
    if usage.has_limits() {
        let bytes = json::encode(&usage).map_err(|e| AiError::Core(crate::Error::Encode(e)))?;
        write_atomic(to, &bytes)?;
    }
    Ok(usage)
}

pub fn load_usage(from: &Path) -> Option<ClaudeUsage> {
    serde_json::from_slice(&fs::read(from).ok()?).ok()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StatusLineState {
    None,
    /// A statusline é o `vibedeck usage record` (com o comando encadeado, se houver).
    Vibedeck {
        previous: Option<String>,
    },
    /// Outra statusline, que será encadeada ao instalar.
    Other(String),
}

const RECORD_MARKER: &str = "usage record";

pub fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

fn read_settings(path: &Path) -> Result<Map<String, Value>> {
    let Ok(bytes) = fs::read(path) else {
        return Ok(Map::new());
    };
    if bytes.is_empty() {
        return Ok(Map::new());
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err(AiError::InvalidClaudeSettings(
            path.to_string_lossy().into_owned(),
        )),
    }
}

fn write_settings(settings: Map<String, Value>, to: &Path) -> Result<()> {
    write_atomic(to, json::to_vdjson(&Value::Object(settings)).as_bytes())?;
    Ok(())
}

/// Extrai o argumento de `--then '<comando>'` gravado por `install_status_line`.
fn previous_command(command: &str) -> Option<String> {
    let at = command.find(" --then ")?;
    let quoted = command[at + " --then ".len()..].trim_matches([' ', '\t']);
    if quoted.chars().count() >= 2 && quoted.starts_with('\'') && quoted.ends_with('\'') {
        let inner = &quoted[1..quoted.len() - 1];
        return Some(inner.replace("'\\''", "'"));
    }
    (!quoted.is_empty()).then(|| quoted.to_string())
}

pub fn status_line_state(settings: &Path) -> Result<StatusLineState> {
    let settings = read_settings(settings)?;
    let command = settings
        .get("statusLine")
        .and_then(|s| s.get("command"))
        .and_then(Value::as_str)
        .filter(|c| !c.is_empty());
    Ok(match command {
        None => StatusLineState::None,
        Some(c) if !c.contains(RECORD_MARKER) => StatusLineState::Other(c.to_string()),
        Some(c) => StatusLineState::Vibedeck {
            previous: previous_command(c),
        },
    })
}

/// Faz a statusline do Claude Code passar pelo `vibedeck usage record`. Uma statusline existente continua
/// aparecendo: vira `--then` e recebe o mesmo JSON.
pub fn install_status_line(executable: &str, settings_file: &Path) -> Result<()> {
    let mut settings = read_settings(settings_file)?;
    let mut command = format!("{} usage record", shell_quote(executable));
    match status_line_state(settings_file)? {
        StatusLineState::None => {}
        StatusLineState::Vibedeck { previous } => {
            if let Some(p) = previous {
                command.push_str(&format!(" --then {}", shell_quote(&p)));
            }
        }
        StatusLineState::Other(p) => command.push_str(&format!(" --then {}", shell_quote(&p))),
    }
    let mut status_line = settings
        .get("statusLine")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    status_line.insert("type".into(), json!("command"));
    status_line.insert("command".into(), json!(command));
    settings.insert("statusLine".into(), Value::Object(status_line));
    write_settings(settings, settings_file)
}

/// Desfaz `install_status_line`, devolvendo a statusline encadeada (se havia uma).
pub fn uninstall_status_line(settings_file: &Path) -> Result<()> {
    let StatusLineState::Vibedeck { previous } = status_line_state(settings_file)? else {
        return Ok(());
    };
    let mut settings = read_settings(settings_file)?;
    match previous {
        Some(p) => {
            let mut status_line = settings
                .get("statusLine")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default();
            status_line.insert("command".into(), json!(p));
            settings.insert("statusLine".into(), Value::Object(status_line));
        }
        None => {
            settings.remove("statusLine");
        }
    }
    write_settings(settings, settings_file)
}

/// Caminho do `vibedeck` a registrar: argv[0] com `/` (normalizado), o primeiro executável do PATH com esse
/// nome ou o binário atual.
pub fn vibedeck_executable_path() -> String {
    let arg0 = std::env::args().next().unwrap_or_else(|| "vibedeck".into());
    if arg0.contains('/') {
        let abs = std::path::absolute(&arg0).unwrap_or_else(|_| PathBuf::from(&arg0));
        return crate::paths::lexical_normalize(&abs)
            .to_string_lossy()
            .into_owned();
    }
    for dir in std::env::var("PATH").unwrap_or_default().split(':') {
        let candidate = Path::new(dir).join(&arg0);
        if candidate.is_file() {
            use std::os::unix::fs::PermissionsExt;
            if candidate
                .metadata()
                .is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
            {
                return candidate.to_string_lossy().into_owned();
            }
        }
    }
    std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or(arg0)
}

#[cfg(test)]
mod tests {
    use super::*;

    const STATUS_LINE: &str = r#"{"session_id":"abc","model":{"id":"claude-opus-5-5","display_name":"Opus"},
     "rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":1791460800},
                    "seven_day":{"used_percentage":18,"resets_at":1791936000}}}"#;

    fn at(secs: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(secs, 0).unwrap()
    }

    #[test]
    fn statusline_grava_e_le_de_volta() {
        let now = at(1_791_450_000);
        let usage = ClaudeUsage::from_status_line(STATUS_LINE.as_bytes(), now).unwrap();
        assert_eq!(usage.model.as_deref(), Some("Opus"));
        assert_eq!(usage.session.unwrap().used_percentage, 42.4);
        assert_eq!(
            usage.session.unwrap().resets_at,
            Some(Timestamp(at(1_791_460_800)))
        );
        assert_eq!(usage.weekly.unwrap().used_percentage, 18.0);
        assert!(usage.summary(now).contains("sessão 42%"));
        assert!(usage.summary(now).contains("semana 18%"));

        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("usage.json");
        record_usage(STATUS_LINE.as_bytes(), &file, now).unwrap();
        assert_eq!(load_usage(&file).unwrap(), usage);
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.contains("\"usedPercentage\" : 18\n"), "{text}");

        // Sem rate_limits o último valor conhecido fica.
        let empty = record_usage(br#"{"model":{"display_name":"Opus"}}"#, &file, now).unwrap();
        assert!(!empty.has_limits());
        assert_eq!(load_usage(&file).unwrap(), usage);
        assert!(matches!(
            ClaudeUsage::from_status_line(b"[]", now),
            Err(AiError::InvalidStatusLine)
        ));
    }

    #[test]
    fn janela_zera_depois_do_reset() {
        let w = Window {
            used_percentage: 80.0,
            resets_at: Some(Timestamp(at(1000))),
        };
        assert_eq!(w.percentage(at(999)), 80.0);
        assert_eq!(w.percentage(at(1000)), 0.0);
    }

    #[test]
    fn instalar_encadeia_a_statusline_existente_e_desinstalar_restaura() {
        let dir = tempfile::tempdir().unwrap();
        let settings = dir.path().join("settings.json");
        fs::write(
            &settings,
            r#"{"model":"opus","statusLine":{"type":"command","command":"echo 'oi'","padding":0}}"#,
        )
        .unwrap();
        install_status_line("/Users/me/.local/bin/vibedeck", &settings).unwrap();
        assert_eq!(
            status_line_state(&settings).unwrap(),
            StatusLineState::Vibedeck {
                previous: Some("echo 'oi'".into())
            }
        );
        let installed: Value = serde_json::from_slice(&fs::read(&settings).unwrap()).unwrap();
        assert_eq!(installed["model"], "opus");
        assert_eq!(installed["statusLine"]["padding"], 0);
        // Reinstalar não encadeia de novo.
        install_status_line("/Users/me/.local/bin/vibedeck", &settings).unwrap();
        assert_eq!(
            status_line_state(&settings).unwrap(),
            StatusLineState::Vibedeck {
                previous: Some("echo 'oi'".into())
            }
        );
        uninstall_status_line(&settings).unwrap();
        assert_eq!(
            status_line_state(&settings).unwrap(),
            StatusLineState::Other("echo 'oi'".into())
        );
    }

    #[test]
    fn instalar_sem_arquivo_e_desinstalar_remove() {
        let dir = tempfile::tempdir().unwrap();
        let settings = dir.path().join("settings.json");
        assert_eq!(status_line_state(&settings).unwrap(), StatusLineState::None);
        install_status_line("vibedeck", &settings).unwrap();
        assert_eq!(
            status_line_state(&settings).unwrap(),
            StatusLineState::Vibedeck { previous: None }
        );
        uninstall_status_line(&settings).unwrap();
        assert_eq!(status_line_state(&settings).unwrap(), StatusLineState::None);
        fs::write(&settings, "[1]").unwrap();
        assert!(matches!(
            install_status_line("vibedeck", &settings),
            Err(AiError::InvalidClaudeSettings(_))
        ));
    }

    #[test]
    fn tokens_distinguem_ausente_zero_cache_e_cumulativo() {
        assert_eq!(TokenUsage::claude(None).input, None);
        let c = TokenUsage::claude(Some(
            &json!({"input_tokens":10,"cache_read_input_tokens":30,"cache_creation_input_tokens":20,"output_tokens":0}),
        ));
        assert_eq!(
            (c.input, c.output, c.cached_input),
            (Some(60), Some(0), Some(30))
        );
        let total = TokenUsage {
            input: Some(1200),
            output: Some(120),
            cached_input: Some(600),
            ..Default::default()
        };
        let base = TokenUsage {
            input: Some(1000),
            output: Some(100),
            cached_input: Some(500),
            ..Default::default()
        };
        assert_eq!(
            total.since(&base),
            TokenUsage {
                input: Some(200),
                output: Some(20),
                cached_input: Some(100),
                ..Default::default()
            }
        );
        assert_eq!(
            TokenUsage::codex(Some(&json!({"inputTokens": -1}))).input,
            None
        );
    }

    #[test]
    fn store_guarda_lista_e_limpa_sem_prompt() {
        let dir = tempfile::tempdir().unwrap();
        let store = UsageStore::new(dir.path());
        let mut a = UsageRecord::new("Teste", Provider::Codex, "secret prompt");
        a.tokens = TokenUsage {
            input: Some(200),
            ..Default::default()
        };
        a.finish("completed");
        store.save(&a).unwrap();
        store.save(&a).unwrap();
        let mut b = UsageRecord::new("Teste", Provider::Codex, "outro");
        b.attempt = 2;
        store.save(&b).unwrap();
        assert_eq!(store.list().unwrap().len(), 2);
        let text = fs::read_to_string(dir.path().join(format!("{}.json", a.id))).unwrap();
        assert!(!text.contains("secret prompt"));
        assert!(text.contains("\"promptCharacters\" : 13"));
        assert!(text.contains("\"taskID\""));
        assert!(usage_line(&a).contains("entrada 200 · saída não informada · completed"));
        store.clear().unwrap();
        assert!(store.list().unwrap().is_empty());
    }
}
