//! Instalação do hook `Stop` (e `SessionStart` no Codex) nos arquivos de configuração dos agentes.
//!
//! Claude Code e Codex usam o mesmo layout (`{"hooks": {"Stop": [{"hooks": [{type, command, timeout}]}]}}`);
//! o JSON é editado preservando todas as outras chaves e hooks (chaves ordenadas, como o Swift).

use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::json;
use crate::store::write_atomic;

use super::error::{Result, RuleError};

const STOP_MARKER: &str = "hook stop";
const SESSION_START_MARKER: &str = "hook start";

/// Agentes cujos hooks falam o mesmo protocolo `Stop` (JSON no stdin, `{"decision":"block"}` no stdout).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HookAgent {
    Claude,
    Codex,
}

impl HookAgent {
    pub const ALL: [HookAgent; 2] = [HookAgent::Claude, HookAgent::Codex];

    pub fn as_str(self) -> &'static str {
        match self {
            HookAgent::Claude => "claude",
            HookAgent::Codex => "codex",
        }
    }

    /// O Codex pode mandar `transcript_path: null`: ganha um `SessionStart` que marca o início da sessão.
    pub fn needs_session_start(self) -> bool {
        self == HookAgent::Codex
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HookScope {
    Local,
    Project,
}

impl HookScope {
    pub const ALL: [HookScope; 2] = [HookScope::Local, HookScope::Project];

    pub fn as_str(self) -> &'static str {
        match self {
            HookScope::Local => "local",
            HookScope::Project => "project",
        }
    }
}

/// Onde cada agente lê os hooks do projeto. O Codex só tem o arquivo versionado (`.codex/hooks.json`).
pub fn hook_file(agent: HookAgent, scope: HookScope, root: &Path) -> Option<PathBuf> {
    match (agent, scope) {
        (HookAgent::Claude, HookScope::Local) => Some(root.join(".claude/settings.local.json")),
        (HookAgent::Claude, HookScope::Project) => Some(root.join(".claude/settings.json")),
        (HookAgent::Codex, HookScope::Project) => Some(root.join(".codex/hooks.json")),
        (HookAgent::Codex, HookScope::Local) => None,
    }
}

/// Arquivo ausente ou vazio = `{}`; que não é um objeto JSON = erro.
fn read_settings(path: &Path) -> Result<Map<String, Value>> {
    let Ok(bytes) = std::fs::read(path) else {
        return Ok(Map::new());
    };
    if bytes.is_empty() {
        return Ok(Map::new());
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err(RuleError::InvalidClaudeSettings(path.display().to_string())),
    }
}

fn write_settings(settings: Map<String, Value>, path: &Path) -> Result<()> {
    let text = json::to_vdjson(&Value::Object(settings));
    write_atomic(path, text.as_bytes())?;
    Ok(())
}

fn hook_entries(settings: &Map<String, Value>, event: &str) -> Vec<Value> {
    settings
        .get("hooks")
        .and_then(Value::as_object)
        .and_then(|h| h.get(event))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn is_vibedeck_hook(entry: &Value, marker: &str) -> bool {
    entry
        .get("hooks")
        .and_then(Value::as_array)
        .is_some_and(|hooks| {
            hooks.iter().any(|h| {
                h.get("command")
                    .and_then(Value::as_str)
                    .is_some_and(|c| c.contains("vibedeck") && c.ends_with(marker))
            })
        })
}

fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// O arquivo de configurações/hooks tem o hook `Stop` do VibeDeck.
pub fn has_stop_hook(settings: &Path) -> Result<bool> {
    let settings = read_settings(settings)?;
    Ok(hook_entries(&settings, "Stop")
        .iter()
        .any(|e| is_vibedeck_hook(e, STOP_MARKER)))
}

/// Acrescenta o hook `Stop` (`<executável> hook stop`) — e `SessionStart` (`<executável> hook start`) com
/// `session_start` — a um settings do Claude Code ou `hooks.json` do Codex, trocando entradas anteriores do
/// VibeDeck e mantendo todos os outros hooks.
pub fn install_stop_hook(
    executable: &str,
    settings_path: &Path,
    session_start: bool,
) -> Result<()> {
    let mut settings = read_settings(settings_path)?;
    let mut hooks = settings
        .get("hooks")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut events = vec![("Stop", STOP_MARKER)];
    if session_start {
        events.push(("SessionStart", SESSION_START_MARKER));
    }
    for (event, marker) in events {
        let mut entries: Vec<Value> = hook_entries(&settings, event)
            .into_iter()
            .filter(|e| !is_vibedeck_hook(e, marker))
            .collect();
        entries.push(json!({"hooks": [{
            "type": "command",
            "command": format!("{} {marker}", shell_quote(executable)),
            "timeout": 600,
        }]}));
        hooks.insert(event.to_string(), Value::Array(entries));
    }
    settings.insert("hooks".to_string(), Value::Object(hooks));
    write_settings(settings, settings_path)
}

/// Remove os hooks `Stop` e `SessionStart` do VibeDeck, descartando chaves que ficarem vazias.
pub fn uninstall_stop_hook(settings_path: &Path) -> Result<()> {
    let mut settings = read_settings(settings_path)?;
    let Some(mut hooks) = settings.get("hooks").and_then(Value::as_object).cloned() else {
        return Ok(());
    };
    for (event, marker) in [
        ("Stop", STOP_MARKER),
        ("SessionStart", SESSION_START_MARKER),
    ] {
        if hooks.contains_key(event) {
            let entries: Vec<Value> = hook_entries(&settings, event)
                .into_iter()
                .filter(|e| !is_vibedeck_hook(e, marker))
                .collect();
            if entries.is_empty() {
                hooks.remove(event);
            } else {
                hooks.insert(event.to_string(), Value::Array(entries));
            }
        }
    }
    if hooks.is_empty() {
        settings.remove("hooks");
    } else {
        settings.insert("hooks".to_string(), Value::Object(hooks));
    }
    write_settings(settings, settings_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(path: &Path) -> Value {
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
    }

    #[test]
    fn install_and_uninstall_keep_other_hooks() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join(".claude/settings.local.json");
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(
            &file,
            r#"{"permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo outro"}]}],"PreToolUse":[{"matcher":"X","hooks":[]}]}}"#,
        )
        .unwrap();
        assert!(!has_stop_hook(&file).unwrap());
        install_stop_hook("/opt/vibedeck", &file, false).unwrap();
        install_stop_hook("/opt/vibedeck", &file, false).unwrap();
        assert!(has_stop_hook(&file).unwrap());
        let v = read(&file);
        let stop = v["hooks"]["Stop"].as_array().unwrap();
        assert_eq!(stop.len(), 2, "outro hook mantido, o nosso não duplica");
        assert_eq!(stop[1]["hooks"][0]["command"], "'/opt/vibedeck' hook stop");
        assert_eq!(stop[1]["hooks"][0]["timeout"], 600);
        assert_eq!(v["permissions"]["allow"][0], "Bash(ls)");
        assert!(v["hooks"].get("SessionStart").is_none());
        uninstall_stop_hook(&file).unwrap();
        assert!(!has_stop_hook(&file).unwrap());
        let v = read(&file);
        assert_eq!(v["hooks"]["Stop"].as_array().unwrap().len(), 1);
        assert!(v["hooks"].get("PreToolUse").is_some());
    }

    #[test]
    fn uninstall_drops_empty_keys_and_file_is_vdjson() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("s.json");
        install_stop_hook("vibedeck", &file, false).unwrap();
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(text.starts_with("{\n  \"hooks\" : {\n    \"Stop\" : ["));
        assert!(text.ends_with("}\n"));
        uninstall_stop_hook(&file).unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "{\n\n}\n");
    }

    #[test]
    fn codex_gets_session_start() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join(".codex/hooks.json");
        install_stop_hook("vibedeck", &file, HookAgent::Codex.needs_session_start()).unwrap();
        let v = read(&file);
        assert_eq!(
            v["hooks"]["SessionStart"][0]["hooks"][0]["command"],
            "'vibedeck' hook start"
        );
        assert_eq!(
            v["hooks"]["Stop"][0]["hooks"][0]["command"],
            "'vibedeck' hook stop"
        );
        uninstall_stop_hook(&file).unwrap();
        let v = read(&file);
        assert!(v.get("hooks").is_none());
    }

    #[test]
    fn invalid_settings_are_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("s.json");
        std::fs::write(&file, "[1,2]").unwrap();
        assert!(matches!(
            has_stop_hook(&file),
            Err(RuleError::InvalidClaudeSettings(_))
        ));
        assert!(install_stop_hook("v", &file, false).is_err());
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "[1,2]");
    }

    #[test]
    fn hook_files_per_agent_and_scope() {
        let root = Path::new("/p");
        assert_eq!(
            hook_file(HookAgent::Claude, HookScope::Local, root),
            Some(PathBuf::from("/p/.claude/settings.local.json"))
        );
        assert_eq!(
            hook_file(HookAgent::Claude, HookScope::Project, root),
            Some(PathBuf::from("/p/.claude/settings.json"))
        );
        assert_eq!(
            hook_file(HookAgent::Codex, HookScope::Project, root),
            Some(PathBuf::from("/p/.codex/hooks.json"))
        );
        assert_eq!(hook_file(HookAgent::Codex, HookScope::Local, root), None);
    }
}
