//! Operações da stack: gravação em `vibedeck.json` (`Store`) e o serviço que fala com o Skill Icons e mantém o
//! bloco do README.md em dia.

use std::collections::BTreeSet;

use serde::Serialize;

use super::icons::{self, SkillBadge, SkillIcon, SkillIconTheme, SkillIconsApi};
use super::{Result, StackError, trim_ws, update_project};
use crate::model::{Author, StackItem};
use crate::store::Store;

fn item_from(icon: &SkillIcon, note: Option<String>, author: Author) -> StackItem {
    StackItem {
        icon: icon.id.clone(),
        name: icon.name.clone(),
        category: icon.category.clone(),
        note,
        tags: vec![],
        author,
    }
}

/// `String.caseInsensitiveCompare == .orderedSame` (aproximado por minúsculas).
fn eq_ignore_case(a: &str, b: &str) -> bool {
    a.to_lowercase() == b.to_lowercase()
}

impl Store {
    /// Índice do item que `reference` nomeia: id exato, depois nome (sem caixa), depois prefixo único do id.
    pub fn stack_index(&self, reference: &str, stack: &[StackItem]) -> Result<usize> {
        let key = trim_ws(reference);
        if let Some(i) = stack.iter().position(|s| s.icon == key) {
            return Ok(i);
        }
        if let Some(i) = stack.iter().position(|s| eq_ignore_case(&s.name, key)) {
            return Ok(i);
        }
        let lower = key.to_lowercase();
        let prefixed: Vec<usize> = (0..stack.len())
            .filter(|&i| stack[i].icon.to_lowercase().starts_with(&lower))
            .collect();
        if prefixed.len() == 1 && !key.is_empty() {
            return Ok(prefixed[0]);
        }
        Err(StackError::StackItemNotFound(reference.to_string()))
    }

    /// Acrescenta ícones que ainda não estão na stack (os existentes mantêm o lugar; uma `note` dada
    /// substitui a deles). Devolve os itens criados ou alterados.
    pub fn add_stack_items(
        &self,
        icons: &[SkillIcon],
        note: Option<&str>,
        author: Author,
    ) -> Result<Vec<StackItem>> {
        let mut touched = Vec::new();
        update_project(self, |project| {
            for icon in icons {
                if let Some(i) = project.stack.iter().position(|s| s.icon == icon.id) {
                    if let Some(note) = note {
                        project.stack[i].note = (!note.is_empty()).then(|| note.to_string());
                    }
                    touched.push(project.stack[i].clone());
                } else {
                    let new = item_from(
                        icon,
                        note.filter(|n| !n.is_empty()).map(str::to_string),
                        author,
                    );
                    project.stack.push(new.clone());
                    touched.push(new);
                }
            }
            Ok(())
        })?;
        Ok(touched)
    }

    /// Remove os itens que `refs` nomeiam. Falha (sem remover nada) se algum não estiver na stack.
    pub fn remove_stack_items(&self, refs: &[String]) -> Result<Vec<StackItem>> {
        let mut removed = Vec::new();
        update_project(self, |project| {
            let mut indices = BTreeSet::new();
            for r in refs {
                indices.insert(self.stack_index(r, &project.stack)?);
            }
            removed = indices.iter().map(|&i| project.stack[i].clone()).collect();
            let old = std::mem::take(&mut project.stack);
            project.stack = old
                .into_iter()
                .enumerate()
                .filter(|(i, _)| !indices.contains(i))
                .map(|(_, s)| s)
                .collect();
            Ok(())
        })?;
        Ok(removed)
    }

    /// Define (ou, com `None`/vazio, apaga) a nota de um item.
    pub fn set_stack_note(&self, reference: &str, note: Option<&str>) -> Result<StackItem> {
        let mut item = None;
        update_project(self, |project| {
            let i = self.stack_index(reference, &project.stack)?;
            project.stack[i].note = note.filter(|n| !n.is_empty()).map(str::to_string);
            item = Some(project.stack[i].clone());
            Ok(())
        })?;
        Ok(item.expect("item definido"))
    }

    /// Substitui as tags do item (vazio remove).
    pub fn set_stack_tags(&self, reference: &str, tags: &[String]) -> Result<StackItem> {
        let mut item = None;
        update_project(self, |project| {
            let i = self.stack_index(reference, &project.stack)?;
            project.stack[i].tags = tags.to_vec();
            item = Some(project.stack[i].clone());
            Ok(())
        })?;
        Ok(item.expect("item definido"))
    }

    /// Move o item para `position` (a partir de 0, limitada ao intervalo).
    pub fn move_stack_item(&self, reference: &str, position: i64) -> Result<()> {
        update_project(self, |project| {
            let i = self.stack_index(reference, &project.stack)?;
            let item = project.stack.remove(i);
            let at = position.clamp(0, project.stack.len() as i64) as usize;
            project.stack.insert(at, item);
            Ok(())
        })?;
        Ok(())
    }
}

/// Resultado de uma mudança: os itens tocados, a stack inteira e um aviso se o README.md não foi atualizado.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Change {
    pub items: Vec<StackItem>,
    pub stack: Vec<StackItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub readme_warning: Option<String>,
}

/// Operações da stack que também falam com o Skill Icons: resolver nomes e manter o badge do README.md.
pub struct StackService<'a> {
    pub store: &'a Store,
    pub icons: &'a dyn SkillIconsApi,
}

impl<'a> StackService<'a> {
    pub fn new(store: &'a Store, icons: &'a dyn SkillIconsApi) -> Self {
        StackService { store, icons }
    }

    pub fn add(&self, refs: &[String], note: Option<&str>, author: Author) -> Result<Change> {
        let catalog = self.icons.catalog()?;
        let resolved = icons::resolve(refs, &catalog)?;
        let items = self.store.add_stack_items(&resolved, note, author)?;
        self.change(items)
    }

    pub fn remove(&self, refs: &[String]) -> Result<Change> {
        let ids = refs
            .iter()
            .map(|r| self.stack_id(r))
            .collect::<Result<Vec<_>>>()?;
        let removed = self.store.remove_stack_items(&ids)?;
        self.change(removed)
    }

    pub fn set_note(&self, reference: &str, note: Option<&str>) -> Result<Change> {
        let id = self.stack_id(reference)?;
        let item = self.store.set_stack_note(&id, note)?;
        self.change(vec![item])
    }

    pub fn move_to(&self, reference: &str, position: i64) -> Result<Change> {
        let id = self.stack_id(reference)?;
        self.store.move_stack_item(&id, position)?;
        let stack = self.store.project()?.stack;
        let i = self.store.stack_index(&id, &stack)?;
        self.change(vec![stack[i].clone()])
    }

    /// O id do item que `reference` nomeia; aliases ("k8s") só passam pelo catálogo se nada casa localmente.
    fn stack_id(&self, reference: &str) -> Result<String> {
        let stack = self.store.project()?.stack;
        if let Ok(i) = self.store.stack_index(reference, &stack) {
            return Ok(stack[i].icon.clone());
        }
        if let Ok(catalog) = self.icons.catalog()
            && let Some(icon) = catalog.iter().find(|i| i.matches_exactly(reference))
            && stack.iter().any(|s| s.icon == icon.id)
        {
            return Ok(icon.id.clone());
        }
        Err(StackError::StackItemNotFound(reference.to_string()))
    }

    /// O badge da stack atual (`None` se vazia).
    pub fn badge(&self, theme: Option<SkillIconTheme>) -> Result<Option<SkillBadge>> {
        let stack = self.store.project()?.stack;
        if stack.is_empty() {
            return Ok(None);
        }
        let ids: Vec<String> = stack.into_iter().map(|s| s.icon).collect();
        Ok(Some(self.icons.badge(&ids, theme, None)?))
    }

    /// Regrava o bloco da stack no README.md. Devolve um aviso em vez de falhar: a stack já está salva.
    pub fn sync_readme(&self) -> Option<String> {
        let result = self.badge(None).and_then(|b| {
            self.store
                .sync_readme_stack(b.as_ref().map(|b| b.markdown.as_str()))
        });
        match result {
            Ok(_) => None,
            Err(e) => Some(format!(
                "A stack foi salva, mas o README.md não foi atualizado: {e}"
            )),
        }
    }

    fn change(&self, items: Vec<StackItem>) -> Result<Change> {
        let readme_warning = self.sync_readme();
        Ok(Change {
            items,
            stack: self.store.project()?.stack,
            readme_warning,
        })
    }
}
