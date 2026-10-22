//! Anexos (`.vibedeck/attachments/<owner>-<nome>[-n].<ext>`) e links Markdown relativos.

use std::path::{Path, PathBuf};

use regex::Regex;

use crate::paths;
use crate::slug;
use crate::store::{Store, write_atomic};

use super::error::{DocError, Result};

const IMAGE_EXTENSIONS: [&str; 10] = [
    "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tif", "tiff", "bmp",
];

pub fn attachments_dir(store: &Store) -> PathBuf {
    store.data_dir().join("attachments")
}

/// Copia `from` para `.vibedeck/attachments/` como `<owner>-<nome>.<ext>` (sufixo `-2`, `-3`... se ocupado).
/// Devolve o link Markdown a inserir, relativo a `docs/` e `ideas/` (`../attachments/...`).
pub fn import_attachment(store: &Store, from: &Path, owner: &str) -> Result<String> {
    let name = from
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let data = std::fs::read(from).map_err(|e| DocError::io(from, e))?;
    import_attachment_data(store, &data, &name, owner)
}

/// Grava `data` (ex.: imagem colada) como anexo nomeado a partir de `name`. Devolve o link Markdown.
pub fn import_attachment_data(
    store: &Store,
    data: &[u8],
    name: &str,
    owner: &str,
) -> Result<String> {
    let dest = attachment_destination(store, name, owner)?;
    write_atomic(&dest, data)?;
    let file_name = dest
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    Ok(attachment_markdown(
        &attachment_path(&file_name, owner),
        name,
    ))
}

fn attachment_destination(store: &Store, name: &str, owner: &str) -> Result<PathBuf> {
    store.ensure_directories()?;
    let leaf = name.rsplit('/').find(|p| !p.is_empty()).unwrap_or(name);
    let path = Path::new(leaf);
    let ext = path
        .extension()
        .map(|e| e.to_string_lossy().into_owned())
        .filter(|e| !e.is_empty())
        .map(|e| slug::make(&e))
        .unwrap_or_default();
    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let dir = attachments_dir(store);
    let base = format!("{}-{}", slug::make(owner), slug::make(&stem));
    let unique = slug::unique(&base, &dir, &ext);
    let file = if ext.is_empty() {
        unique
    } else {
        format!("{unique}.{ext}")
    };
    // O diretório de anexos não pode redirecionar a escrita para fora de `.vibedeck`.
    Ok(paths::contained(&store.data_dir(), &dir, &file)?)
}

/// `![nome](caminho)` para imagens (renderizadas na prévia), `[nome](caminho)` para o resto.
pub fn attachment_markdown(path: &str, name: &str) -> String {
    let label = name.replace('[', "(").replace(']', ")");
    let ext = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    let image = IMAGE_EXTENSIONS.contains(&ext.as_str());
    format!("{}[{label}]({path})", if image { "!" } else { "" })
}

/// `attachmentPath`: `../` por componente do `owner` + `attachments/<arquivo>`.
pub fn attachment_path(name: &str, owner: &str) -> String {
    let depth = owner.split('/').filter(|p| !p.is_empty()).count();
    format!("{}attachments/{name}", "../".repeat(depth))
}

/// `markdownForGroupedRecord`: reescreve (só para exibir) o prefixo `../` dos links de anexos conforme a
/// profundidade de `reference`; nunca regrava o Markdown guardado.
pub fn markdown_for_grouped_record(text: &str, reference: &str) -> String {
    let depth = reference.split('/').filter(|p| !p.is_empty()).count();
    let prefix = "../".repeat(depth);
    let re = Regex::new(r"\((?:\.\./)+attachments/").expect("regex fixa");
    re.replace_all(text, |_: &regex::Captures| format!("({prefix}attachments/"))
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markdown_variants() {
        assert_eq!(
            attachment_markdown("../attachments/a.png", "a[1].png"),
            "![a(1).png](../attachments/a.png)"
        );
        assert_eq!(
            attachment_markdown("../attachments/a.pdf", "a.pdf"),
            "[a.pdf](../attachments/a.pdf)"
        );
        assert_eq!(
            attachment_path("f.png", "a/b/x"),
            "../../../attachments/f.png"
        );
    }

    #[test]
    fn rebase_for_display() {
        assert_eq!(
            markdown_for_grouped_record("![F](../attachments/f.png)", "a/b/x"),
            "![F](../../../attachments/f.png)"
        );
        assert_eq!(
            markdown_for_grouped_record("[x](../../attachments/f.png) (../attachments/z)", "x"),
            "[x](../attachments/f.png) (../attachments/z)"
        );
    }
}
