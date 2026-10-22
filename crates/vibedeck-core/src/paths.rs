//! Validação de caminhos gerenciados (`normalizedGroupPath`, `canonicalURL`, `containedURL`,
//! `validatedRecordURL`). Nada aqui segue symlinks que escapem da pasta do conceito.

use std::collections::HashSet;
use std::path::{Component, Path, PathBuf};

use crate::error::{Error, Result};
use crate::slug;

/// Rejeita travessia antes da normalização: vazio (salvo `allow_root`), `/` inicial, `\`, componentes
/// vazios, `.`, `..` ou ocultos (`.x`). Devolve o caminho com cada componente passado por `Slug.make`.
pub fn normalize_group_path(path: &str, allow_root: bool) -> Result<String> {
    if path.is_empty() && allow_root {
        return Ok(String::new());
    }
    let invalid = path.is_empty()
        || path.starts_with('/')
        || path.contains('\\')
        || path.contains('\0')
        || path
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == ".." || p.starts_with('.'));
    if invalid {
        return Err(Error::InvalidGroupPath(path.to_string()));
    }
    Ok(path
        .split('/')
        .map(slug::make)
        .collect::<Vec<_>>()
        .join("/"))
}

/// Resolve `.` e `..` só lexicalmente (como `standardizedFileURL`).
pub fn lexical_normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::ParentDir => {
                if !out.pop() {
                    out.push("..");
                }
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Caminho canônico mesmo quando o final não existe: resolve o maior ancestral existente (seguindo symlinks
/// pendentes) e anexa os componentes que faltam. Essencial para criar arquivos com segurança.
pub fn canonical(path: &Path) -> PathBuf {
    let abs = std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf());
    let mut ancestor = lexical_normalize(&abs);
    let mut missing: Vec<std::ffi::OsString> = Vec::new();
    let mut seen: HashSet<PathBuf> = HashSet::new();
    while !ancestor.exists() && ancestor.parent().is_some() {
        if let Ok(target) = std::fs::read_link(&ancestor)
            && seen.insert(ancestor.clone())
        {
            let next = if target.is_absolute() {
                target
            } else {
                ancestor.parent().map(|p| p.join(&target)).unwrap_or(target)
            };
            ancestor = lexical_normalize(&next);
            continue;
        }
        match ancestor.file_name() {
            Some(name) => missing.push(name.to_os_string()),
            None => break,
        }
        ancestor.pop();
    }
    let mut resolved = std::fs::canonicalize(&ancestor).unwrap_or(ancestor);
    for c in missing.into_iter().rev() {
        resolved.push(c);
    }
    lexical_normalize(&resolved)
}

/// `containedURL`: `dir` (pasta do conceito) tem de ficar dentro de `data_dir` (`.vibedeck`) e o caminho
/// final `dir/rel` (resolvido, inclusive symlinks pendentes) tem de ficar dentro de `dir`.
pub fn contained(data_dir: &Path, dir: &Path, rel: &str) -> Result<PathBuf> {
    let bad = || Error::InvalidGroupPath(rel.to_string());
    let base = canonical(dir);
    let data = canonical(data_dir);
    if base == data || !base.starts_with(&data) {
        return Err(bad());
    }
    let url = lexical_normalize(&base.join(rel));
    let resolved = canonical(&url);
    if resolved != base && !resolved.starts_with(&base) {
        return Err(bad());
    }
    Ok(url)
}

/// `validatedRecordURL`: valida a referência e devolve `dir/<referência>.<ext>` contido na pasta.
pub fn validated_record_path(
    data_dir: &Path,
    dir: &Path,
    reference: &str,
    ext: &str,
) -> Result<PathBuf> {
    normalize_group_path(reference, false)?;
    contained(data_dir, dir, &format!("{reference}.{ext}"))
}

/// Caminho de `file` relativo a `dir`, ambos canônicos, com `/` (sem extensão se `strip_ext`).
pub fn relative_to(dir: &Path, file: &Path, strip_ext: bool) -> Option<String> {
    let base = canonical(dir);
    let mut f = canonical(file);
    if strip_ext {
        f.set_extension("");
    }
    let rel = f.strip_prefix(&base).ok()?;
    Some(
        rel.components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .collect::<Vec<_>>()
            .join("/"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn group_path_validation() {
        for bad in [
            "", "/abs", "a\\b", "a//b", "./a", "a/./b", "../x", "a/../b", "a/..", ".oculto", "a/.b",
        ] {
            assert!(
                matches!(
                    normalize_group_path(bad, false),
                    Err(Error::InvalidGroupPath(_))
                ),
                "{bad:?} deveria ser inválido"
            );
        }
        assert_eq!(normalize_group_path("", true).unwrap(), "");
        assert_eq!(
            normalize_group_path("Criação do Core/Minha Ideia", false).unwrap(),
            "criacao-do-core/minha-ideia"
        );
    }

    struct Env {
        _tmp: tempfile::TempDir,
        data: PathBuf,
        dir: PathBuf,
        outside: PathBuf,
    }

    fn env() -> Env {
        let tmp = tempfile::tempdir().unwrap();
        let root = fs::canonicalize(tmp.path()).unwrap();
        let data = root.join(".vibedeck");
        let dir = data.join("ideas");
        let outside = root.join("fora");
        fs::create_dir_all(&dir).unwrap();
        fs::create_dir_all(&outside).unwrap();
        Env {
            _tmp: tmp,
            data,
            dir,
            outside,
        }
    }

    #[test]
    fn plain_and_new_paths_are_contained() {
        let e = env();
        let p = validated_record_path(&e.data, &e.dir, "grupo/nova", "json").unwrap();
        assert_eq!(p, e.dir.join("grupo/nova.json"));
    }

    #[test]
    fn dotdot_escapes_are_rejected() {
        let e = env();
        assert!(validated_record_path(&e.data, &e.dir, "../x", "json").is_err());
        assert!(validated_record_path(&e.data, &e.dir, "a/../../x", "json").is_err());
        // contained() sozinho também barra o escape lexical
        assert!(contained(&e.data, &e.dir, "../../fora/x.json").is_err());
        assert!(contained(&e.data, &e.dir, "../ideas-irma/x.json").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn symlink_dir_to_outside_is_rejected() {
        use std::os::unix::fs::symlink;
        let e = env();
        symlink(&e.outside, e.dir.join("link")).unwrap();
        assert!(matches!(
            validated_record_path(&e.data, &e.dir, "link/x", "json"),
            Err(Error::InvalidGroupPath(_))
        ));
        // symlink de arquivo para fora (existente)
        fs::write(e.outside.join("alvo.json"), "{}").unwrap();
        symlink(e.outside.join("alvo.json"), e.dir.join("arq.json")).unwrap();
        assert!(validated_record_path(&e.data, &e.dir, "arq", "json").is_err());
        // symlink pendente para fora
        symlink(e.outside.join("nao-existe.json"), e.dir.join("pend.json")).unwrap();
        assert!(validated_record_path(&e.data, &e.dir, "pend", "json").is_err());
        // symlink encadeado
        symlink(e.dir.join("link"), e.dir.join("link2")).unwrap();
        assert!(validated_record_path(&e.data, &e.dir, "link2/x", "json").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn symlink_inside_concept_is_allowed() {
        use std::os::unix::fs::symlink;
        let e = env();
        fs::create_dir_all(e.dir.join("real")).unwrap();
        symlink(e.dir.join("real"), e.dir.join("atalho")).unwrap();
        let p = validated_record_path(&e.data, &e.dir, "atalho/x", "json").unwrap();
        assert_eq!(canonical(&p), e.dir.join("real/x.json"));
    }

    #[cfg(unix)]
    #[test]
    fn concept_dir_symlinked_outside_is_rejected() {
        use std::os::unix::fs::symlink;
        let e = env();
        let rules = e.data.join("rules");
        symlink(&e.outside, &rules).unwrap();
        assert!(validated_record_path(&e.data, &rules, "x", "json").is_err());
    }

    #[test]
    fn relative_paths() {
        let e = env();
        fs::create_dir_all(e.dir.join("g")).unwrap();
        let f = e.dir.join("g/a.json");
        fs::write(&f, "{}").unwrap();
        assert_eq!(relative_to(&e.dir, &f, true).unwrap(), "g/a");
        assert_eq!(relative_to(&e.dir, &f, false).unwrap(), "g/a.json");
    }
}
