//! O bloco `<!-- vibedeck:stack:start/end -->` que o VibeDeck mantém no README.md com o badge da stack.

use std::fs;

use super::Result;
use crate::store::{Store, write_atomic};

pub struct ReadmeStack;

impl ReadmeStack {
    pub const START: &'static str = "<!-- vibedeck:stack:start -->";
    pub const END: &'static str = "<!-- vibedeck:stack:end -->";

    /// `text` com o bloco ajustado para `badge` (`None` remove). Bloco novo vai logo depois do primeiro
    /// título `# `, ou no topo quando não há título.
    pub fn apply(badge: Option<&str>, text: &str) -> String {
        if let Some((s_lo, s_hi)) = marker_line(Self::START, text, 0)
            && let Some((_, e_hi)) = marker_line(Self::END, text, s_hi)
        {
            let mut remove_end = e_hi;
            if text.as_bytes().get(remove_end) == Some(&b'\n') {
                remove_end += 1;
            }
            let mut out = String::with_capacity(text.len());
            match badge {
                None => {
                    out.push_str(&text[..s_lo]);
                    let mut rest = &text[remove_end..];
                    // Tira a linha em branco que o bloco deixa para trás.
                    if out.ends_with("\n\n") && rest.starts_with('\n') {
                        rest = &rest[1..];
                    }
                    out.push_str(rest);
                }
                Some(b) => {
                    out.push_str(&text[..s_lo]);
                    out.push_str(&block(b));
                    out.push('\n');
                    out.push_str(&text[remove_end..]);
                }
            }
            return out;
        }
        let Some(badge) = badge else {
            return text.to_string();
        };
        let mut lines: Vec<&str> = text.split('\n').collect();
        let blk = block(badge);
        if let Some(heading) = lines.iter().position(|l| l.starts_with("# ")) {
            lines.insert(heading + 1, "");
            lines.insert(heading + 2, &blk);
            return lines.join("\n");
        }
        let tail = if text.is_empty() {
            String::new()
        } else {
            format!("\n{text}")
        };
        format!("{blk}\n{tail}")
    }
}

fn block(badge: &str) -> String {
    format!("{}\n{badge}\n{}", ReadmeStack::START, ReadmeStack::END)
}

/// A primeira ocorrência de `marker` que ocupa uma linha inteira (um marcador citado em prosa é ignorado).
fn marker_line(marker: &str, text: &str, from: usize) -> Option<(usize, usize)> {
    let bytes = text.as_bytes();
    let mut from = from;
    while let Some(rel) = text[from..].find(marker) {
        let lo = from + rel;
        let hi = lo + marker.len();
        // No Swift, "\r\n" é um único Character e não conta como "\n".
        let at_start = lo == 0 || (bytes[lo - 1] == b'\n' && (lo < 2 || bytes[lo - 2] != b'\r'));
        let at_end = hi == text.len() || bytes[hi] == b'\n';
        if at_start && at_end {
            return Some((lo, hi));
        }
        from = hi;
    }
    None
}

impl Store {
    pub fn readme_path(&self) -> std::path::PathBuf {
        self.root().join("README.md")
    }

    /// Grava `badge` (Markdown do Skill Icons) no bloco da stack do README.md; `None` remove o bloco. Só cria
    /// o README.md quando há o que mostrar. Devolve se o arquivo mudou.
    pub fn sync_readme_stack(&self, badge: Option<&str>) -> Result<bool> {
        let current = fs::read_to_string(self.readme_path()).ok();
        if current.is_none() && badge.is_none() {
            return Ok(false);
        }
        let base = match &current {
            Some(c) => c.clone(),
            None => format!("# {}\n", self.project()?.name),
        };
        let updated = ReadmeStack::apply(badge, &base);
        if current.as_deref() == Some(updated.as_str()) {
            return Ok(false);
        }
        write_atomic(&self.readme_path(), updated.as_bytes())?;
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const S: &str = ReadmeStack::START;
    const E: &str = ReadmeStack::END;

    #[test]
    fn marcadores_citados_em_prosa_sao_ignorados() {
        let prose = format!("# T\n\nUse `{S}` e `{E}`.\n");
        let applied = ReadmeStack::apply(Some("B"), &prose);
        assert_eq!(
            applied,
            format!("# T\n\n{S}\nB\n{E}\n\nUse `{S}` e `{E}`.\n")
        );
        assert_eq!(ReadmeStack::apply(None, &applied), prose);
    }

    #[test]
    fn bloco_sem_titulo() {
        assert_eq!(
            ReadmeStack::apply(Some("B"), "texto\n"),
            format!("{S}\nB\n{E}\n\ntexto\n")
        );
        assert_eq!(ReadmeStack::apply(None, "texto\n"), "texto\n");
        assert_eq!(ReadmeStack::apply(Some("B"), ""), format!("{S}\nB\n{E}\n"));
    }

    #[test]
    fn troca_e_remove_bloco_existente() {
        let t = format!("# Demo\n\n{S}\nA\n{E}\n\nTexto.\n");
        assert_eq!(
            ReadmeStack::apply(Some("B"), &t),
            format!("# Demo\n\n{S}\nB\n{E}\n\nTexto.\n")
        );
        assert_eq!(ReadmeStack::apply(None, &t), "# Demo\n\nTexto.\n");
        // sem linha em branco depois do bloco: nada a recolher
        let t2 = format!("# Demo\n{S}\nA\n{E}\nTexto.\n");
        assert_eq!(ReadmeStack::apply(None, &t2), "# Demo\nTexto.\n");
    }

    #[test]
    fn sync_cria_atualiza_e_remove() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::init(dir.path(), "Demo", None).unwrap();
        // nada a mostrar e sem README: não cria
        assert!(!store.sync_readme_stack(None).unwrap());
        assert!(!store.readme_path().exists());
        assert!(store.sync_readme_stack(Some("![Stack](u)")).unwrap());
        let readme = fs::read_to_string(store.readme_path()).unwrap();
        assert_eq!(readme, format!("# Demo\n\n{S}\n![Stack](u)\n{E}\n"));
        assert!(!store.sync_readme_stack(Some("![Stack](u)")).unwrap());
        assert!(store.sync_readme_stack(None).unwrap());
        // o Swift deixa a linha em branco quando o bloco era o fim do arquivo
        assert_eq!(
            fs::read_to_string(store.readme_path()).unwrap(),
            "# Demo\n\n"
        );
    }
}
