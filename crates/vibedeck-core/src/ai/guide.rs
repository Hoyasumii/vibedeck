//! Guia embutido (`AgentsGuide.swift`): `AGENTS.md` (curto, lido em toda sessão) e `guide.md` (referência
//! completa, lida por seção). Sem as seções de sessões de nuvem (D5).

use std::fs;
use std::sync::OnceLock;

use super::{AiError, Result, context};
use crate::model::project::SCHEMA_BASE;
use crate::store::{Store, write_atomic};

const REFERENCE_TEMPLATE: &str = include_str!("guide_reference.md");

/// Guia completo (`guide.md`).
pub fn reference_markdown() -> &'static str {
    static REFERENCE: OnceLock<String> = OnceLock::new();
    REFERENCE.get_or_init(|| REFERENCE_TEMPLATE.replace("{SCHEMA_BASE}", SCHEMA_BASE))
}

/// Seções `## ...` do guia, cada uma com o próprio cabeçalho.
pub fn sections() -> Vec<String> {
    reference_markdown()
        .split("\n## ")
        .skip(1)
        .map(|s| format!("## {s}"))
        .collect()
}

pub fn section(index: i64) -> Option<String> {
    if index < 0 {
        return None;
    }
    sections().into_iter().nth(index as usize)
}

/// `0: Regras — ...` por seção, uma por linha.
pub fn index() -> String {
    sections()
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let title = s.split('\n').next().unwrap_or("");
            format!("{i}: {}", title.get(3..).unwrap_or(""))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// `AGENTS.md`: a parte obrigatória (antes de `## Stack`) mais política de IA e índice do guia.
pub fn markdown() -> String {
    let mandatory = reference_markdown()
        .split("\n## Stack")
        .next()
        .unwrap_or_default();
    format!(
        "{mandatory}\n\n## Trabalho eficiente com IA\n\n{}\n\n## Antes de implementar\n\nConsulte revisões abertas. CLI/MCP: author=ai; preserve dados humanos, ids e schemas.\nNão edite guia nem checks. Promova ideias só a pedido. Workflows/importações: provider\n(codex no Codex); respeite modelo, permissões, transições, decisões do usuário e limites.\n\n## Documentação sob demanda\n\nLeia só a seção necessária: `vibedeck ai guide --section <n>`, MCP `ai_guide(section: n)` ou o título em\n`.vibedeck/guide.md`. Registros: `vibedeck ai catalog <tipo>` / MCP `ai_catalog`; abra só o que for usar.\n\n{}",
        context::INSTRUCTIONS,
        index()
    )
}

/// Grava `AGENTS.md` e `guide.md` (cria `.vibedeck/` se faltar).
pub fn write_agents_guide(store: &Store) -> Result<()> {
    let data = store.data_dir();
    fs::create_dir_all(&data).map_err(|e| AiError::io(&data, e))?;
    write_atomic(&data.join("AGENTS.md"), markdown().as_bytes())?;
    write_atomic(&data.join("guide.md"), reference_markdown().as_bytes())?;
    Ok(())
}

/// Reescreve `AGENTS.md`/`guide.md` só quando diferem do guia embutido (o Swift faz isso no start do CLI e
/// do MCP, ignorando erros). Devolve `true` se escreveu.
pub fn refresh_agents_guide(store: &Store) -> Result<bool> {
    let data = store.data_dir();
    let agents_ok = fs::read(data.join("AGENTS.md")).is_ok_and(|b| b == markdown().as_bytes());
    let guide_ok =
        fs::read(data.join("guide.md")).is_ok_and(|b| b == reference_markdown().as_bytes());
    if agents_ok && guide_ok {
        return Ok(false);
    }
    write_agents_guide(store)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guia_reduz_contexto_sem_perder_documentacao() {
        let md = markdown();
        assert!((md.chars().count() as f64) / (reference_markdown().chars().count() as f64) < 0.70);
        assert!(md.len() <= 3_900, "AGENTS.md tem {} bytes", md.len());
        for contract in [
            "rules_for",
            "submit_rule_check",
            "passed",
            "verify_manual",
            "pending",
            "provider",
            "modelo",
        ] {
            assert!(md.contains(contract), "{contract}");
        }
        assert!(sections().iter().all(|s| reference_markdown().contains(s)));
    }

    #[test]
    fn politica_compartilhada_aparece_uma_vez() {
        assert_eq!(markdown().matches(context::INSTRUCTIONS).count(), 1);
    }

    #[test]
    fn sem_secoes_de_nuvem() {
        for text in [markdown(), reference_markdown().to_string()] {
            let lower = text.to_lowercase();
            assert!(!lower.contains("nuvem"), "nuvem");
            assert!(!lower.contains("cloud"), "cloud");
        }
        assert!(!index().contains("nuvem"));
    }

    #[test]
    fn indice_e_secoes() {
        let idx = index();
        assert!(idx.starts_with("0: "));
        assert_eq!(idx.lines().count(), sections().len());
        assert!(section(0).unwrap().starts_with("## "));
        assert!(section(sections().len() as i64).is_none());
        assert!(section(-1).is_none());
        assert!(reference_markdown().contains(&format!("{SCHEMA_BASE}/{{project,")));
    }
}
