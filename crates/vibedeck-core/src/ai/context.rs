//! `AIPromptPolicy` e `AIContextStore` (AIPromptPolicy.swift): política compartilhada de prompts e
//! instantâneos imutáveis de contexto, lidos por páginas sem perder o restante.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::{AiError, Result, graphemes, local_store_dir, sha256_hex};
use crate::store::write_atomic;

pub const POLICY_VERSION: u32 = 2;

/// Instruções comuns a toda instalação e provider. Nunca reescrevem instruções do usuário.
pub const INSTRUCTIONS: &str = include_str!("policy_instructions.txt");

pub const INCOMPLETE: &str = "A resposta continua incompleta após uma recuperação. Amplie o contexto ou escolha um modelo mais capaz.";

pub fn prompt(task: &str, context: &str, output: &str) -> String {
    format!(
        "{INSTRUCTIONS}\n\n## Tarefa\n{task}\n\n## Contexto\n{context}\n\n## Saída obrigatória\n{output}"
    )
}

pub fn recovery(original: &str, diagnosis: &str) -> String {
    format!(
        "{original}\n\n## Recuperação única\nA resposta não cumpriu o contrato: {diagnosis}. Releia as fontes pertinentes e amplie a busca. Corrija a resposta completa, sem inventar evidências."
    )
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reference {
    pub id: String,
    pub title: String,
    pub path: String,
    pub characters: usize,
}

impl Reference {
    pub fn instruction(&self) -> String {
        format!(
            "{}: {} caracteres. Fonte completa: `{}`. Leia por trechos ou use `vibedeck ai context {} --offset 0 --limit 4000`; MCP: ai_context(id: {}). Conteúdo omitido aqui, não descartado.",
            self.title, self.characters, self.path, self.id, self.id
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Page {
    pub text: String,
    pub offset: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_offset: Option<usize>,
    pub total_characters: usize,
}

#[derive(Debug, Clone)]
pub struct ContextStore {
    pub directory: PathBuf,
}

impl ContextStore {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        ContextStore {
            directory: directory.into(),
        }
    }

    /// `AIContextStore(root:)`: `<dados da máquina>/ai/<hash da raiz>/context`.
    pub fn for_root(root: &Path) -> Self {
        ContextStore::new(local_store_dir(root).join("context"))
    }

    pub fn save(&self, text: &str, title: &str) -> Result<Reference> {
        let id = sha256_hex(text.as_bytes());
        fs::create_dir_all(&self.directory).map_err(|e| AiError::io(&self.directory, e))?;
        let file = self.directory.join(format!("{id}.txt"));
        if !file.exists() {
            write_atomic(&file, text.as_bytes())?;
        }
        Ok(Reference {
            id,
            title: title.to_string(),
            path: file.to_string_lossy().into_owned(),
            characters: graphemes::count(text),
        })
    }

    /// `offset >= 0` e `limit` em 1...16000; contagem em caracteres (grafemas), sem perder o restante.
    pub fn page(&self, id: &str, offset: i64, limit: i64) -> Result<Page> {
        let valid_id =
            id.chars().count() == 64 && id.chars().all(|c| matches!(c, '0'..='9' | 'a'..='f'));
        if !valid_id || offset < 0 || !(1..=16000).contains(&limit) {
            return Err(AiError::InvalidRange);
        }
        let file = self.directory.join(format!("{id}.txt"));
        let text = fs::read_to_string(&file).map_err(|e| AiError::io(&file, e))?;
        let clusters = graphemes::clusters(&text);
        let (offset, limit) = (offset as usize, limit as usize);
        if offset > clusters.len() {
            return Err(AiError::InvalidRange);
        }
        let end = (offset + limit).min(clusters.len());
        let part: String = clusters[offset..end].concat();
        Ok(Page {
            text: part,
            offset,
            next_offset: (end < clusters.len()).then_some(end),
            total_characters: clusters.len(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paginas_sem_perda_e_confinadas() {
        let dir = tempfile::tempdir().unwrap();
        let store = ContextStore::new(dir.path());
        let text = "Decisão: não apagar 👩🏽‍💻.\n".repeat(400);
        let r = store.save(&text, "Decisões").unwrap();
        assert_eq!(store.save(&text, "Outro título").unwrap().id, r.id);
        let (mut recovered, mut offset) = (String::new(), 0i64);
        loop {
            let page = store.page(&r.id, offset, 73).unwrap();
            recovered.push_str(&page.text);
            match page.next_offset {
                Some(n) => offset = n as i64,
                None => break,
            }
        }
        assert_eq!(recovered, text);
        assert!(matches!(
            store.page("../../secret", 0, 4000),
            Err(AiError::InvalidRange)
        ));
        assert!(matches!(
            store.page(&r.id, -1, 4000),
            Err(AiError::InvalidRange)
        ));
        assert!(matches!(
            store.page(&r.id, 0, 0),
            Err(AiError::InvalidRange)
        ));
        assert!(store.page(&"0".repeat(64), 0, 4000).is_err());
    }

    #[test]
    fn politica_aparece_no_prompt() {
        assert!(prompt("t", "c", "o").starts_with(INSTRUCTIONS));
        assert!(
            recovery("x", "d")
                .contains("## Recuperação única\nA resposta não cumpriu o contrato: d. ")
        );
    }
}
