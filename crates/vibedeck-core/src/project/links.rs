//! Links do projeto (`vibedeck.json`).

use super::{ProjectError, Result};
use crate::model::{Id, Link};
use crate::store::Store;

pub fn list(store: &Store) -> Result<Vec<Link>> {
    Ok(store.project()?.links)
}

/// `Link(title: title ?? url, …)`: título ausente vira a URL. Sem validação de URL.
pub fn add(store: &Store, url: &str, title: Option<&str>, tags: Vec<String>) -> Result<Link> {
    let link = Link {
        id: Id::new(),
        title: title.unwrap_or(url).to_string(),
        url: url.to_string(),
        tags,
    };
    let mut project = store.project()?;
    project.links.push(link.clone());
    store.save_project(&project)?;
    Ok(link)
}

/// Remove todos os links cujo id (maiúsculas ou minúsculas) começa com `id`. Nenhum → erro e nada é gravado.
/// Atenção: prefixo vazio casa com todos (igual ao Swift).
pub fn remove(store: &Store, id: &str) -> Result<usize> {
    let mut project = store.project()?;
    let needle = id.to_lowercase();
    let before = project.links.len();
    project
        .links
        .retain(|l| !l.id.to_string().to_lowercase().starts_with(&needle));
    let removed = before - project.links.len();
    if removed == 0 {
        return Err(ProjectError::LinkNotFound(id.to_string()));
    }
    store.save_project(&project)?;
    Ok(removed)
}

/// `hashtags(tags)`: vazio → `""`, senão `"  #a #b"`.
pub fn hashtags(tags: &[String]) -> String {
    if tags.is_empty() {
        String::new()
    } else {
        format!("  #{}", tags.join(" #"))
    }
}

/// `uuidString.prefix(8)` (maiúsculas).
pub fn id8(id: &Id) -> String {
    id.to_string().chars().take(8).collect()
}
