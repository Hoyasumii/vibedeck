//! Leitura dos arquivos nativos dos provedores: Markdown com frontmatter do Claude Code
//! (`.claude/agents|commands|skills`, `.codex/prompts`) e TOML dos agentes do Codex (`.codex/agents`).

use std::collections::HashMap;

use super::error::{ResourceError, Result};

fn trimmed(s: &str) -> &str {
    s.trim()
}

fn non_empty(s: &str) -> Option<String> {
    (!s.is_empty()).then(|| s.to_string())
}

/// Frontmatter como o Claude Code escreve: pares `chave: valor` no topo, blocos `|`/`>` de várias linhas e
/// listas `- item`. Não é um parser YAML; só tolerante o bastante para arquivos escritos à mão.
pub struct Frontmatter {
    pub fields: HashMap<String, String>,
    pub body: String,
}

impl Frontmatter {
    /// Chaves em minúsculas → valores crus, e o corpo depois do `---` final (o texto todo sem frontmatter).
    pub fn parse(text: &str) -> Frontmatter {
        let normalized = text.replace("\r\n", "\n");
        let lines: Vec<&str> = normalized.split('\n').collect();
        let mut fields = HashMap::new();
        let end = if lines.first().map(|l| trimmed(l)) == Some("---") {
            lines
                .iter()
                .skip(1)
                .position(|l| trimmed(l) == "---")
                .map(|p| p + 1)
        } else {
            None
        };
        let Some(end) = end else {
            return Frontmatter {
                fields,
                body: text.to_string(),
            };
        };
        let mut key: Option<String> = None;
        let mut buffer: Vec<String> = Vec::new();
        let mut block = false;
        let flush = |key: &Option<String>,
                     buffer: &mut Vec<String>,
                     block: bool,
                     fields: &mut HashMap<String, String>| {
            if let Some(k) = key {
                let joined = if block {
                    buffer.join("\n")
                } else {
                    buffer.join(" ")
                };
                fields.insert(k.clone(), trimmed(&joined).to_string());
            }
            buffer.clear();
        };
        for line in &lines[1..end] {
            let is_top =
                !line.chars().next().is_none_or(char::is_whitespace) && !line.starts_with('-');
            if is_top && let Some(colon) = line.find(':') {
                flush(&key, &mut buffer, block, &mut fields);
                key = Some(trimmed(&line[..colon]).to_lowercase());
                let rest = trimmed(&line[colon + 1..]);
                block = matches!(rest, "|" | ">" | "|-" | ">-");
                buffer = if rest.is_empty() || block {
                    vec![]
                } else {
                    vec![rest.to_string()]
                };
            } else {
                buffer.push(trimmed(line).to_string());
            }
        }
        flush(&key, &mut buffer, block, &mut fields);
        Frontmatter {
            fields,
            body: lines[end + 1..].join("\n"),
        }
    }

    pub fn unquote(s: &str) -> String {
        let s = trimmed(s);
        let chars: Vec<char> = s.chars().collect();
        if chars.len() >= 2 {
            let f = chars[0];
            if f == chars[chars.len() - 1] && (f == '"' || f == '\'') {
                return chars[1..chars.len() - 1].iter().collect();
            }
        }
        s.to_string()
    }

    /// Escalar não vazio e sem aspas.
    pub fn value(&self, key: &str) -> Option<String> {
        self.fields
            .get(key)
            .and_then(|v| non_empty(&Self::unquote(v)))
    }

    /// Lista separada por vírgula, quebra de linha ou `- item` (`tools: Read, Grep` ou lista YAML).
    pub fn list(&self, key: &str) -> Vec<String> {
        self.fields
            .get(key)
            .map(String::as_str)
            .unwrap_or("")
            .split([',', '\n'])
            .map(|item| Self::unquote(item.trim().trim_matches(['-', ' ', '[', ']'])))
            .filter(|s| !s.is_empty())
            .collect()
    }
}

/// Resultado comum da leitura de um arquivo de agente/comando/skill.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Parsed {
    pub name: String,
    pub description: Option<String>,
    pub argument_hint: Option<String>,
    pub model: Option<String>,
    /// Só agentes do Codex (`model_reasoning_effort`).
    pub effort: Option<String>,
    pub tools: Vec<String>,
    pub prompt: String,
}

/// Agente do Claude Code: `name`, `description`, `model`, `tools`; o corpo é o prompt.
pub fn parse_claude_agent(text: &str, fallback_name: &str) -> Parsed {
    let fm = Frontmatter::parse(text);
    Parsed {
        name: fm
            .value("name")
            .unwrap_or_else(|| fallback_name.to_string()),
        description: fm.value("description"),
        model: fm.value("model"),
        tools: fm.list("tools"),
        prompt: trimmed(&fm.body).to_string(),
        ..Parsed::default()
    }
}

/// Comando (slash command): `description`, `argument-hint`, `allowed-tools`, `model`; o corpo é o prompt.
pub fn parse_claude_command(text: &str, fallback_name: &str) -> Parsed {
    let fm = Frontmatter::parse(text);
    Parsed {
        name: fm
            .value("name")
            .unwrap_or_else(|| fallback_name.to_string()),
        description: fm.value("description"),
        argument_hint: fm.value("argument-hint"),
        model: fm.value("model"),
        tools: fm.list("allowed-tools"),
        prompt: trimmed(&fm.body).to_string(),
        ..Parsed::default()
    }
}

/// `SKILL.md`: `name`, `description`, `allowed-tools`, `model`; o nome cai para a pasta.
pub fn parse_claude_skill(text: &str, fallback_name: &str) -> Parsed {
    let fm = Frontmatter::parse(text);
    Parsed {
        name: fm
            .value("name")
            .unwrap_or_else(|| fallback_name.to_string()),
        description: fm.value("description"),
        model: fm.value("model"),
        tools: fm.list("allowed-tools"),
        prompt: trimmed(&fm.body).to_string(),
        ..Parsed::default()
    }
}

/// Campos string do TOML de agentes do Codex (inclui strings multilinha básicas/literais). O resto do
/// arquivo fica onde está e nunca é interpretado como permissão do VibeDeck.
pub fn parse_codex_agent(text: &str, fallback_name: &str) -> Result<Parsed> {
    const WANTED: [&str; 5] = [
        "name",
        "description",
        "model",
        "model_reasoning_effort",
        "developer_instructions",
    ];
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0usize;
    let mut fields: HashMap<String, String> = HashMap::new();
    let invalid = || ResourceError::Codex(format!("TOML inválido no agente {fallback_name}"));
    let skip_line = |i: &mut usize| {
        while *i < chars.len() && chars[*i] != '\n' {
            *i += 1;
        }
    };
    while i < chars.len() {
        while i < chars.len() && chars[i].is_whitespace() {
            i += 1;
        }
        if i >= chars.len() {
            break;
        }
        if chars[i] == '#' {
            skip_line(&mut i);
            continue;
        }
        // Só os campos da raiz descrevem o agente; tabelas aninhadas são configuração opcional.
        if chars[i] == '[' {
            break;
        }
        let begin = i;
        while i < chars.len() && chars[i] != '=' && chars[i] != '\n' {
            i += 1;
        }
        if i >= chars.len() || chars[i] != '=' {
            return Err(invalid());
        }
        let raw_key: String = chars[begin..i].iter().collect();
        let key = raw_key
            .trim_matches([' ', '\t'])
            .trim_matches(['"', '\''])
            .to_string();
        i += 1;
        while i < chars.len() && (chars[i] == ' ' || chars[i] == '\t') {
            i += 1;
        }
        if i >= chars.len() {
            return Err(invalid());
        }
        if chars[i] != '"' && chars[i] != '\'' {
            if WANTED.contains(&key.as_str()) {
                return Err(invalid());
            }
            skip_line(&mut i);
            continue;
        }
        let quote = chars[i];
        let triple = i + 2 < chars.len() && chars[i + 1] == quote && chars[i + 2] == quote;
        i += if triple { 3 } else { 1 };
        if triple && i < chars.len() && chars[i] == '\n' {
            i += 1;
        }
        let mut value = String::new();
        let mut closed = false;
        while i < chars.len() {
            if chars[i] == quote
                && (!triple
                    || (i + 2 < chars.len() && chars[i + 1] == quote && chars[i + 2] == quote))
            {
                i += if triple { 3 } else { 1 };
                closed = true;
                break;
            }
            if !triple && chars[i] == '\n' {
                return Err(invalid());
            }
            if chars[i] == '\\' && quote == '"' {
                i += 1;
                if i >= chars.len() {
                    return Err(invalid());
                }
                let c = chars[i];
                i += 1;
                match c {
                    'n' => value.push('\n'),
                    'r' => value.push('\r'),
                    't' => value.push('\t'),
                    'b' => value.push('\u{08}'),
                    'f' => value.push('\u{0c}'),
                    '"' => value.push('"'),
                    '\\' => value.push('\\'),
                    'u' | 'U' => {
                        let count = if c == 'u' { 4 } else { 8 };
                        if i + count > chars.len() {
                            return Err(invalid());
                        }
                        let hex: String = chars[i..i + count].iter().collect();
                        let scalar = u32::from_str_radix(&hex, 16)
                            .ok()
                            .and_then(char::from_u32)
                            .ok_or_else(invalid)?;
                        value.push(scalar);
                        i += count;
                    }
                    '\n' | '\r' | ' ' | '\t' => {
                        if !triple {
                            return Err(invalid());
                        }
                        while i < chars.len() && chars[i].is_whitespace() {
                            i += 1;
                        }
                    }
                    _ => return Err(invalid()),
                }
            } else {
                value.push(chars[i]);
                i += 1;
            }
        }
        if !closed {
            return Err(invalid());
        }
        if WANTED.contains(&key.as_str()) {
            if fields.contains_key(&key) {
                return Err(invalid());
            }
            fields.insert(key, value);
        }
        while i < chars.len() && matches!(chars[i], ' ' | '\t' | '\r') {
            i += 1;
        }
        if i < chars.len() && chars[i] == '#' {
            skip_line(&mut i);
        }
        if i < chars.len() && chars[i] != '\n' {
            return Err(invalid());
        }
    }
    let prompt = fields
        .get("developer_instructions")
        .filter(|p| !p.trim().is_empty())
        .cloned()
        .ok_or_else(|| {
            ResourceError::Codex(format!(
                "Agente {fallback_name} sem developer_instructions."
            ))
        })?;
    Ok(Parsed {
        name: fields
            .get("name")
            .cloned()
            .unwrap_or_else(|| fallback_name.to_string()),
        description: fields.get("description").cloned(),
        model: fields.get("model").cloned(),
        effort: fields.get("model_reasoning_effort").cloned(),
        prompt,
        ..Parsed::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_file_with_block_description() {
        let text = "---\nname: code-explorer\ndescription: |\n  Analisa features.\n  Segunda linha.\ntools: Glob, Grep, Read\nmodel: sonnet\ncolor: yellow\n---\n\nVocê é um analista.";
        let p = parse_claude_agent(text, "x");
        assert_eq!(p.name, "code-explorer");
        assert_eq!(
            p.description.as_deref(),
            Some("Analisa features.\nSegunda linha.")
        );
        assert_eq!(p.tools, ["Glob", "Grep", "Read"]);
        assert_eq!(p.model.as_deref(), Some("sonnet"));
        assert_eq!(p.prompt, "Você é um analista.");
        assert_eq!(parse_claude_agent("só prompt", "fb").name, "fb");
    }

    #[test]
    fn skill_file_and_bare_text() {
        let text = "---\nname: revisar-pr\ndescription: Use ao revisar um pull request\nallowed-tools: Read, Grep, Bash(gh pr diff:*)\nmodel: sonnet\n---\n\n# Revisar PR\n\nLeia o diff.";
        let p = parse_claude_skill(text, "pasta");
        assert_eq!(p.name, "revisar-pr");
        assert_eq!(p.tools, ["Read", "Grep", "Bash(gh pr diff:*)"]);
        assert_eq!(p.prompt, "# Revisar PR\n\nLeia o diff.");
        let bare = parse_claude_skill("Só as instruções", "pasta");
        assert_eq!(bare.name, "pasta");
        assert_eq!(bare.prompt, "Só as instruções");
        assert!(bare.description.is_none());
    }

    #[test]
    fn command_file_reads_hint_and_yaml_list() {
        let text = "---\ndescription: \"Faz commit\"\nargument-hint: <mensagem>\nallowed-tools: Bash(git add:*), Bash(git commit:*)\n---\nCommite $ARGUMENTS";
        let p = parse_claude_command(text, "git:commit");
        assert_eq!(p.name, "git:commit");
        assert_eq!(p.description.as_deref(), Some("Faz commit"));
        assert_eq!(p.argument_hint.as_deref(), Some("<mensagem>"));
        assert_eq!(p.tools, ["Bash(git add:*)", "Bash(git commit:*)"]);
        assert_eq!(p.prompt, "Commite $ARGUMENTS");
    }

    #[test]
    fn codex_toml_native_and_invalid() {
        let p = parse_codex_agent(
            "name = \"rev\"\ndescription = 'Revisa'\nmodel = \"m\"\nmodel_reasoning_effort = \"high\"\ndeveloper_instructions = \"\"\"\nLinha 1\nLinha 2\n\"\"\"\n[tools]\nx = 1\n",
            "fb",
        )
        .unwrap();
        assert_eq!(p.name, "rev");
        assert_eq!(p.description.as_deref(), Some("Revisa"));
        assert_eq!(p.effort.as_deref(), Some("high"));
        assert_eq!(p.prompt, "Linha 1\nLinha 2\n");
        assert!(parse_codex_agent("name = 'bad'", "bad").is_err());
        assert!(parse_codex_agent("developer_instructions = \"unterminated", "bad").is_err());
        let u = parse_codex_agent(r#"developer_instructions = "Olá\nRevise""#, "unicode").unwrap();
        assert_eq!(u.prompt, "Olá\nRevise");
        assert_eq!(u.name, "unicode");
    }
}
