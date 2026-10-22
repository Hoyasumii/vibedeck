//! Persistência: descoberta da raiz, leitura tolerante, escrita atômica e API por tipo.
//!
//! Regras (dados.md §1, §2.4, R14): arquivo que não decodifica é **ignorado** nas listagens e **erro** no
//! `load`; escrita = temp no mesmo diretório + `rename`, sob um mutex de processo; um registro cujos bytes
//! não mudam nunca é regravado; gravações tipadas descartam chaves desconhecidas (como o Swift).

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::error::{Error, Result};
use crate::json;
use crate::model::*;
use crate::paths;
use crate::slug::{self, Candidate};

pub const PROJECT_FILE: &str = "vibedeck.json";
pub const DATA_DIR: &str = ".vibedeck";

static WRITE_LOCK: Mutex<()> = Mutex::new(());
static TMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Grava `bytes` em `path` de forma atômica (temp no mesmo diretório + `rename`; cria os pais). Se `path`
/// é um symlink, o alvo é resolvido antes e o link continua link.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let _guard = WRITE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let target = resolve_link_target(path);
    let parent = target.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent).map_err(|e| Error::io(parent, e))?;
    let name = target
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let tmp = parent.join(format!(
        ".{name}.{}.{}.tmp",
        std::process::id(),
        TMP_COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut f = fs::File::create_new(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        drop(f);
        fs::rename(&tmp, &target)
    })();
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(Error::io(&target, e));
    }
    Ok(())
}

fn resolve_link_target(path: &Path) -> PathBuf {
    match fs::symlink_metadata(path) {
        Ok(m) if m.file_type().is_symlink() => fs::canonicalize(path).unwrap_or_else(|_| {
            // pendente: segue a cadeia uma vez
            match fs::read_link(path) {
                Ok(t) if t.is_absolute() => t,
                Ok(t) => path.parent().map(|p| p.join(&t)).unwrap_or(t),
                Err(_) => path.to_path_buf(),
            }
        }),
        _ => path.to_path_buf(),
    }
}

/// Grava só se os bytes diferem do que já está no disco. Devolve `true` se escreveu.
pub fn write_if_changed(path: &Path, bytes: &[u8]) -> Result<bool> {
    if let Ok(existing) = fs::read(path)
        && existing == bytes
    {
        return Ok(false);
    }
    write_atomic(path, bytes)?;
    Ok(true)
}

/// Um registro lido, com o slug (caminho relativo à pasta do conceito, sem `.json`).
#[derive(Debug, Clone, PartialEq)]
pub struct Record<T> {
    pub slug: String,
    pub value: T,
}

/// Arquivo ignorado numa listagem por não decodificar.
#[derive(Debug)]
pub struct Skipped {
    pub path: PathBuf,
    pub error: String,
}

#[derive(Debug)]
pub struct Listing<T> {
    pub records: Vec<Record<T>>,
    pub skipped: Vec<Skipped>,
}

/// Tipo gravado como um arquivo `.json` por slug dentro de `.vibedeck/<DIR>/`.
pub trait Stored: Serialize + DeserializeOwned {
    /// Subpasta de `.vibedeck`.
    const DIR: &'static str;
    /// `true` lê subpastas (grupos); `false` só o diretório (agents, commands, workflows).
    const RECURSIVE: bool;
    fn not_found(reference: &str) -> Error;
    fn title(&self) -> &str;
    fn id(&self) -> Id;
    fn created_at(&self) -> Timestamp;
}

macro_rules! stored {
    ($ty:ty, $dir:literal, $rec:literal, $err:ident) => {
        impl Stored for $ty {
            const DIR: &'static str = $dir;
            const RECURSIVE: bool = $rec;
            fn not_found(r: &str) -> Error {
                Error::$err(r.to_string())
            }
            fn title(&self) -> &str {
                &self.title
            }
            fn id(&self) -> Id {
                self.id
            }
            fn created_at(&self) -> Timestamp {
                self.created_at
            }
        }
    };
}
stored!(ReviewGroup, "reviews", true, GroupNotFound);
stored!(RuleTopic, "rules", true, TopicNotFound);
stored!(Idea, "ideas", true, IdeaNotFound);
stored!(Skill, "skills", true, SkillNotFound);
stored!(Agent, "agents", false, AgentNotFound);
stored!(Command, "commands", false, CommandNotFound);
stored!(Workflow, "workflows", false, WorkflowNotFound);

/// Execução de workflow lida do disco; `reference` = `<workflow>/<run>`.
#[derive(Debug, Clone, PartialEq)]
pub struct RunRecord {
    pub reference: String,
    pub run: WorkflowRun,
}

/// Check lido do disco com o nome do arquivo.
#[derive(Debug, Clone, PartialEq)]
pub struct CheckRecord {
    pub file_name: String,
    pub check: RuleCheck,
}

#[derive(Debug, Clone)]
pub struct Store {
    root: PathBuf,
}

impl Store {
    /// Abre a raiz `root` (precisa conter `vibedeck.json`).
    pub fn open(root: impl AsRef<Path>) -> Result<Store> {
        let root = std::path::absolute(root.as_ref()).map_err(|e| Error::io(root.as_ref(), e))?;
        if !root.join(PROJECT_FILE).is_file() {
            return Err(Error::NotAProject(root.display().to_string()));
        }
        Ok(Store { root })
    }

    /// Sobe diretórios a partir de `start` até achar um `vibedeck.json`.
    pub fn find_root(start: impl AsRef<Path>) -> Option<PathBuf> {
        let start = std::path::absolute(start.as_ref()).ok()?;
        let mut cur: &Path = &start;
        loop {
            if cur.join(PROJECT_FILE).is_file() {
                return Some(cur.to_path_buf());
            }
            cur = cur.parent()?;
        }
    }

    pub fn discover(start: impl AsRef<Path>) -> Result<Store> {
        match Self::find_root(start.as_ref()) {
            Some(root) => Store::open(root),
            None => Err(Error::NotAProject(start.as_ref().display().to_string())),
        }
    }

    /// Cria `vibedeck.json` novo e as pastas de `.vibedeck`.
    pub fn init(root: impl AsRef<Path>, name: &str, description: Option<String>) -> Result<Store> {
        let root = std::path::absolute(root.as_ref()).map_err(|e| Error::io(root.as_ref(), e))?;
        if root.join(PROJECT_FILE).exists() {
            return Err(Error::AlreadyAProject(root.display().to_string()));
        }
        fs::create_dir_all(&root).map_err(|e| Error::io(&root, e))?;
        let store = Store { root };
        store.save_project(&Project::new(name, description))?;
        store.ensure_directories()?;
        Ok(store)
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn data_dir(&self) -> PathBuf {
        self.root.join(DATA_DIR)
    }

    pub fn dir<T: Stored>(&self) -> PathBuf {
        self.data_dir().join(T::DIR)
    }

    pub fn checks_dir(&self) -> PathBuf {
        self.data_dir().join("checks")
    }

    pub fn runs_dir(&self) -> PathBuf {
        self.data_dir().join("runs")
    }

    /// `docs reviews rules ideas agents commands skills workflows checks attachments` (não cria `tests/` nem `runs/`).
    pub fn ensure_directories(&self) -> Result<()> {
        for d in [
            "docs",
            "reviews",
            "rules",
            "ideas",
            "agents",
            "commands",
            "skills",
            "workflows",
            "checks",
            "attachments",
        ] {
            let p = self.data_dir().join(d);
            fs::create_dir_all(&p).map_err(|e| Error::io(&p, e))?;
        }
        Ok(())
    }

    // ---- projeto -------------------------------------------------------------------------------

    pub fn project(&self) -> Result<Project> {
        let path = self.root.join(PROJECT_FILE);
        let bytes = fs::read(&path).map_err(|e| Error::io(&path, e))?;
        serde_json::from_slice(&bytes).map_err(|source| Error::Decode { path, source })
    }

    /// Grava `vibedeck.json`; devolve `false` se os bytes não mudaram.
    pub fn save_project(&self, project: &Project) -> Result<bool> {
        let bytes = json::encode(project).map_err(Error::Encode)?;
        write_if_changed(&self.root.join(PROJECT_FILE), &bytes)
    }

    // ---- genérico por slug ---------------------------------------------------------------------

    pub fn record_path<T: Stored>(&self, slug: &str) -> Result<PathBuf> {
        paths::validated_record_path(&self.data_dir(), &self.dir::<T>(), slug, "json")
    }

    /// Arquivos regulares `*.json` (extensão em minúsculas), sem ocultos nem symlinks, contidos na pasta.
    fn record_files<T: Stored>(&self) -> Result<Vec<PathBuf>> {
        let dir = self.dir::<T>();
        if !dir.is_dir() {
            return Ok(vec![]);
        }
        let mut out = Vec::new();
        collect_json(&self.data_dir(), &dir, &dir, T::RECURSIVE, &mut out)?;
        out.sort();
        Ok(out)
    }

    /// Lista com os arquivos ignorados, ordenada por `(createdAt, slug)`.
    pub fn list_with_skipped<T: Stored>(&self) -> Result<Listing<T>> {
        let dir = self.dir::<T>();
        let mut records = Vec::new();
        let mut skipped = Vec::new();
        for file in self.record_files::<T>()? {
            let bytes = fs::read(&file).map_err(|e| Error::io(&file, e))?;
            match serde_json::from_slice::<T>(&bytes) {
                Ok(value) => {
                    if let Some(slug) = paths::relative_to(&dir, &file, true) {
                        records.push(Record { slug, value });
                    }
                }
                Err(e) => skipped.push(Skipped {
                    path: file,
                    error: e.to_string(),
                }),
            }
        }
        records
            .sort_by(|a, b| (a.value.created_at(), &a.slug).cmp(&(b.value.created_at(), &b.slug)));
        Ok(Listing { records, skipped })
    }

    pub fn list<T: Stored>(&self) -> Result<Vec<Record<T>>> {
        Ok(self.list_with_skipped::<T>()?.records)
    }

    /// Lê um registro pelo slug exato. Arquivo inexistente = "não encontrado"; que não decodifica = erro.
    pub fn load<T: Stored>(&self, slug: &str) -> Result<T> {
        let path = self.record_path::<T>(slug)?;
        if !path.exists() {
            return Err(T::not_found(slug));
        }
        let bytes = fs::read(&path).map_err(|e| Error::io(&path, e))?;
        serde_json::from_slice(&bytes).map_err(|source| Error::Decode { path, source })
    }

    /// Resolve slug, id/prefixo (>= 4) ou título para o slug do registro.
    pub fn resolve<T: Stored>(&self, reference: &str) -> Result<String> {
        let candidates: Vec<Candidate> = self
            .list::<T>()?
            .into_iter()
            .map(|r| Candidate {
                slug: r.slug,
                id: r.value.id(),
                title: r.value.title().to_string(),
            })
            .collect();
        let found = slug::resolve(reference, &candidates, |r| {
            Ok(self.record_path::<T>(r)?.exists())
        })?;
        found.ok_or_else(|| T::not_found(reference))
    }

    pub fn find<T: Stored>(&self, reference: &str) -> Result<Record<T>> {
        let slug = self.resolve::<T>(reference)?;
        let value = self.load::<T>(&slug)?;
        Ok(Record { slug, value })
    }

    /// Grava `value` em `slug`. `false` = bytes idênticos aos do disco (nada foi regravado).
    pub fn save<T: Stored>(&self, slug: &str, value: &T) -> Result<bool> {
        let path = self.record_path::<T>(slug)?;
        let bytes = json::encode(value).map_err(Error::Encode)?;
        write_if_changed(&path, &bytes)
    }

    pub fn delete<T: Stored>(&self, slug: &str) -> Result<()> {
        let path = self.record_path::<T>(slug)?;
        if !path.exists() {
            return Err(T::not_found(slug));
        }
        fs::remove_file(&path).map_err(|e| Error::io(&path, e))
    }

    /// Slug livre para um registro novo: `Slug.make(title)` ou, com `reference` (caminho com grupos), cada
    /// componente passa por `Slug.make`; sempre `uniqueSlug`.
    pub fn new_slug<T: Stored>(&self, title: &str, reference: Option<&str>) -> Result<String> {
        let dir = self.dir::<T>();
        match reference {
            None => {
                let base = slug::make(title);
                let slug = slug::unique(&base, &dir, "json");
                self.record_path::<T>(&slug)?;
                Ok(slug)
            }
            Some(r) => {
                let norm = paths::normalize_group_path(r, false)?;
                let (group, leaf) = match norm.rsplit_once('/') {
                    Some((g, l)) => (Some(g), l),
                    None => (None, norm.as_str()),
                };
                // valida contenção da referência original antes de olhar o disco
                paths::contained(&self.data_dir(), &dir, &format!("{r}.json"))?;
                let parent = group.map_or(dir.clone(), |g| dir.join(g));
                let unique = slug::unique(leaf, &parent, "json");
                Ok(group.map_or(unique.clone(), |g| format!("{g}/{unique}")))
            }
        }
    }

    /// Cria o registro num slug novo e devolve `(slug)`.
    pub fn create<T: Stored + Clone>(
        &self,
        value: &T,
        reference: Option<&str>,
    ) -> Result<Record<T>> {
        let slug = self.new_slug::<T>(value.title(), reference)?;
        self.save(&slug, value)?;
        Ok(Record {
            slug,
            value: value.clone(),
        })
    }

    // ---- checks (histórico imutável) -----------------------------------------------------------

    /// Mais novo primeiro, por `(createdAt, mtime)`. Arquivos que não decodificam são ignorados.
    pub fn checks(&self) -> Result<Vec<CheckRecord>> {
        let dir = self.checks_dir();
        if !dir.is_dir() {
            return Ok(vec![]);
        }
        let mut items = Vec::new();
        for entry in fs::read_dir(&dir).map_err(|e| Error::io(&dir, e))? {
            let entry = entry.map_err(|e| Error::io(&dir, e))?;
            let name = entry.file_name().to_string_lossy().into_owned();
            let Ok(ft) = entry.file_type() else { continue };
            if name.starts_with('.') || !ft.is_file() || !name.to_lowercase().ends_with(".json") {
                continue;
            }
            let path = entry.path();
            if paths::contained(&self.data_dir(), &dir, &name).is_err() {
                continue;
            }
            let Ok(bytes) = fs::read(&path) else { continue };
            let Ok(check) = serde_json::from_slice::<RuleCheck>(&bytes) else {
                continue;
            };
            let mtime = entry
                .metadata()
                .and_then(|m| m.modified())
                .unwrap_or(std::time::UNIX_EPOCH);
            items.push((
                mtime,
                CheckRecord {
                    file_name: name,
                    check,
                },
            ));
        }
        items.sort_by(|a, b| {
            (b.1.check.created_at, b.0, &b.1.file_name).cmp(&(
                a.1.check.created_at,
                a.0,
                &a.1.file_name,
            ))
        });
        Ok(items.into_iter().map(|(_, r)| r).collect())
    }

    /// Grava um check novo; nunca reescreve um existente. Devolve o nome do arquivo.
    pub fn save_check(&self, check: &RuleCheck) -> Result<String> {
        let name = check.file_name();
        let path = paths::contained(&self.data_dir(), &self.checks_dir(), &name)?;
        if path.symlink_metadata().is_ok() {
            return Err(Error::CheckExists(name));
        }
        let bytes = json::encode(check).map_err(Error::Encode)?;
        write_atomic(&path, &bytes)?;
        Ok(name)
    }

    // ---- runs ----------------------------------------------------------------------------------

    fn run_file(&self, workflow: &str, run: &str) -> Result<PathBuf> {
        for part in [workflow, run] {
            if part.is_empty() || part.contains(['/', '\\', '\0']) || part.starts_with('.') {
                return Err(Error::InvalidGroupPath(format!("{workflow}/{run}")));
            }
        }
        paths::contained(
            &self.data_dir(),
            &self.runs_dir(),
            &format!("{workflow}/{run}/run.json"),
        )
    }

    /// Todas as execuções, mais recentes primeiro por `(updatedAt, ref)`. Pastas que não são run são ignoradas.
    pub fn runs(&self) -> Result<Vec<RunRecord>> {
        let base = self.runs_dir();
        let mut out = Vec::new();
        for wf in visible_dirs(&base)? {
            for run in visible_dirs(&base.join(&wf))? {
                let Ok(file) = self.run_file(&wf, &run) else {
                    continue;
                };
                let Ok(bytes) = fs::read(&file) else { continue };
                if let Ok(r) = serde_json::from_slice::<WorkflowRun>(&bytes) {
                    out.push(RunRecord {
                        reference: format!("{wf}/{run}"),
                        run: r,
                    });
                }
            }
        }
        out.sort_by(|a, b| (b.run.updated_at, &b.reference).cmp(&(a.run.updated_at, &a.reference)));
        Ok(out)
    }

    pub fn load_run(&self, workflow: &str, run: &str) -> Result<WorkflowRun> {
        let path = self.run_file(workflow, run)?;
        if !path.exists() {
            return Err(Error::RunNotFound(format!("{workflow}/{run}")));
        }
        let bytes = fs::read(&path).map_err(|e| Error::io(&path, e))?;
        serde_json::from_slice(&bytes).map_err(|source| Error::Decode { path, source })
    }

    pub fn save_run(&self, workflow: &str, run: &str, value: &WorkflowRun) -> Result<bool> {
        let path = self.run_file(workflow, run)?;
        let bytes = json::encode(value).map_err(Error::Encode)?;
        write_if_changed(&path, &bytes)
    }
}

fn visible_dirs(dir: &Path) -> Result<Vec<String>> {
    if !dir.is_dir() {
        return Ok(vec![]);
    }
    let mut names = Vec::new();
    for entry in fs::read_dir(dir).map_err(|e| Error::io(dir, e))? {
        let entry = entry.map_err(|e| Error::io(dir, e))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        if entry.file_type().is_ok_and(|t| t.is_dir()) {
            names.push(name);
        }
    }
    names.sort();
    Ok(names)
}

fn collect_json(
    data_dir: &Path,
    root: &Path,
    dir: &Path,
    recursive: bool,
    out: &mut Vec<PathBuf>,
) -> Result<()> {
    for entry in fs::read_dir(dir).map_err(|e| Error::io(dir, e))? {
        let entry = entry.map_err(|e| Error::io(dir, e))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_symlink() {
            continue; // nunca segue symlinks (arquivo ou diretório)
        }
        let path = entry.path();
        if ft.is_dir() {
            if recursive {
                collect_json(data_dir, root, &path, recursive, out)?;
            }
        } else if ft.is_file()
            && path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("json"))
        {
            let rel = paths::relative_to(root, &path, false).unwrap_or(name);
            paths::contained(data_dir, root, &rel)?;
            out.push(path);
        }
    }
    Ok(())
}

macro_rules! typed_api {
    ($(($ty:ty, $list:ident, $get:ident, $save:ident, $del:ident)),* $(,)?) => {
        impl Store {
            $(
                pub fn $list(&self) -> Result<Vec<Record<$ty>>> { self.list::<$ty>() }
                /// Resolve por slug, id/prefixo ou título.
                pub fn $get(&self, reference: &str) -> Result<Record<$ty>> { self.find::<$ty>(reference) }
                /// Grava no slug dado; `false` = bytes iguais, nada regravado.
                pub fn $save(&self, slug: &str, value: &$ty) -> Result<bool> { self.save::<$ty>(slug, value) }
                pub fn $del(&self, slug: &str) -> Result<()> { self.delete::<$ty>(slug) }
            )*
        }
    };
}

typed_api!(
    (
        ReviewGroup,
        review_groups,
        review_group,
        save_review_group,
        delete_review_group
    ),
    (
        RuleTopic,
        rule_topics,
        rule_topic,
        save_rule_topic,
        delete_rule_topic
    ),
    (Idea, ideas, idea, save_idea, delete_idea),
    (Skill, skills, skill, save_skill, delete_skill),
    (Agent, agents, agent, save_agent, delete_agent),
    (Command, commands, command, save_command, delete_command),
    (
        Workflow,
        workflows,
        workflow,
        save_workflow,
        delete_workflow
    ),
);

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> (tempfile::TempDir, Store) {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::init(tmp.path(), "demo", None).unwrap();
        (tmp, store)
    }

    #[test]
    fn init_open_discover() {
        let (tmp, store) = fresh();
        assert!(matches!(
            Store::init(tmp.path(), "x", None),
            Err(Error::AlreadyAProject(_))
        ));
        let deep = tmp.path().join("a/b/c");
        fs::create_dir_all(&deep).unwrap();
        let found = Store::discover(&deep).unwrap();
        assert_eq!(found.root(), store.root());
        let empty = tempfile::tempdir().unwrap();
        // pode haver um vibedeck.json acima do tmp? improvável; só confere o tipo do erro quando não há
        if Store::find_root(empty.path()).is_none() {
            assert!(matches!(
                Store::discover(empty.path()),
                Err(Error::NotAProject(_))
            ));
        }
        assert_eq!(store.project().unwrap().name, "demo");
    }

    #[test]
    fn save_is_noop_when_bytes_equal() {
        let (_t, store) = fresh();
        let mut g = ReviewGroup::new("Tema");
        g.items.push(ReviewItem::new("note", "Um"));
        let slug = store.new_slug::<ReviewGroup>(&g.title, None).unwrap();
        assert_eq!(slug, "tema");
        assert!(store.save_review_group(&slug, &g).unwrap());
        let path = store.dir::<ReviewGroup>().join("tema.json");
        let m1 = fs::metadata(&path).unwrap().modified().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        assert!(!store.save_review_group(&slug, &g).unwrap());
        assert_eq!(fs::metadata(&path).unwrap().modified().unwrap(), m1);
        g.title = "Outro".into();
        assert!(store.save_review_group(&slug, &g).unwrap());
        let again = store.new_slug::<ReviewGroup>("Tema", None).unwrap();
        assert_eq!(again, "tema-2");
    }

    #[test]
    fn list_skips_undecodable_but_load_errors() {
        let (_t, store) = fresh();
        let dir = store.dir::<Idea>();
        fs::write(dir.join("quebrada.json"), "{ nao e json").unwrap();
        fs::write(dir.join(".oculta.json"), "{}").unwrap();
        fs::write(dir.join("sem-titulo.json"), "{}").unwrap();
        store.save_idea("boa", &Idea::new("Boa")).unwrap();
        let listing = store.list_with_skipped::<Idea>().unwrap();
        assert_eq!(listing.records.len(), 1);
        assert_eq!(listing.skipped.len(), 2);
        assert!(matches!(
            store.load::<Idea>("quebrada"),
            Err(Error::Decode { .. })
        ));
        assert!(matches!(
            store.load::<Idea>("nada"),
            Err(Error::IdeaNotFound(_))
        ));
    }

    #[test]
    fn groups_recursion_and_resolve() {
        let (_t, store) = fresh();
        let a = Idea::new("Alfa");
        let b = Idea::new("Beta");
        store.create(&a, None).unwrap();
        let rec = store.create(&b, Some("grupo/Minha Ideia")).unwrap();
        assert_eq!(rec.slug, "grupo/minha-ideia");
        let slugs: Vec<_> = store.ideas().unwrap().into_iter().map(|r| r.slug).collect();
        assert!(
            slugs.contains(&"alfa".to_string()) && slugs.contains(&"grupo/minha-ideia".to_string())
        );
        assert_eq!(store.idea("minha-ideia").unwrap().slug, "grupo/minha-ideia");
        let prefix = b.id.to_string()[..6].to_lowercase();
        assert_eq!(store.idea(&prefix).unwrap().slug, "grupo/minha-ideia");
        assert_eq!(store.idea("alfa").unwrap().value.title, "Alfa");
        assert!(matches!(store.idea("zzz"), Err(Error::IdeaNotFound(_))));
        assert!(matches!(
            store.idea("../fora"),
            Err(Error::InvalidGroupPath(_))
        ));
    }

    #[test]
    fn flat_concepts_do_not_recurse() {
        let (_t, store) = fresh();
        store.save_agent("a", &Agent::new("A")).unwrap();
        let sub = store.dir::<Agent>().join("sub");
        fs::create_dir_all(&sub).unwrap();
        fs::write(
            sub.join("x.json"),
            serde_json::to_string(&Agent::new("X")).unwrap(),
        )
        .unwrap();
        assert_eq!(store.agents().unwrap().len(), 1);
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_are_not_listed_or_followed() {
        use std::os::unix::fs::symlink;
        let (tmp, store) = fresh();
        let outside = tmp.path().join("fora");
        fs::create_dir_all(&outside).unwrap();
        fs::write(
            outside.join("i.json"),
            serde_json::to_string(&Idea::new("Fora")).unwrap(),
        )
        .unwrap();
        symlink(&outside, store.dir::<Idea>().join("grupo")).unwrap();
        symlink(
            outside.join("i.json"),
            store.dir::<Idea>().join("link.json"),
        )
        .unwrap();
        assert!(store.ideas().unwrap().is_empty());
        assert!(store.save_idea("grupo/x", &Idea::new("X")).is_err());
        assert!(store.load::<Idea>("link").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn atomic_write_keeps_symlink() {
        use std::os::unix::fs::symlink;
        let tmp = tempfile::tempdir().unwrap();
        let real = tmp.path().join("real.md");
        fs::write(&real, "a").unwrap();
        let link = tmp.path().join("link.md");
        symlink(&real, &link).unwrap();
        write_atomic(&link, b"novo").unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs::read(&real).unwrap(), b"novo");
        // nenhum temporário sobrando
        let left: Vec<_> = fs::read_dir(tmp.path()).unwrap().collect();
        assert_eq!(left.len(), 2);
    }

    #[test]
    fn checks_are_append_only_and_newest_first() {
        let (_t, store) = fresh();
        let mk = |ts: &str| RuleCheck {
            schema: None,
            id: Id::new(),
            task: "t".into(),
            files: vec![],
            topics: vec![],
            review_item: None,
            results: vec![],
            passed: true,
            warnings: vec![],
            failures: vec![],
            pending: vec![],
            author: Author::Ai,
            created_at: TimestampMs(crate::time::parse_iso(ts).unwrap()),
        };
        let old = mk("2026-10-09T03:17:31.836Z");
        let new = mk("2026-10-10T00:00:00.000Z");
        let n_old = store.save_check(&old).unwrap();
        store.save_check(&new).unwrap();
        assert!(n_old.starts_with("20261009-031731-"));
        assert!(matches!(store.save_check(&old), Err(Error::CheckExists(_))));
        let list = store.checks().unwrap();
        assert_eq!(list[0].check.id, new.id);
        assert_eq!(list[1].check.id, old.id);
    }

    #[test]
    fn runs_roundtrip_and_validation() {
        let (_t, store) = fresh();
        let wf = Workflow::new("W");
        store.save_workflow("w", &wf).unwrap();
        let json = r#"{"workflow":"w","status":"running","current":"a"}"#;
        let run: WorkflowRun = serde_json::from_str(json).unwrap();
        assert!(store.save_run("w", "exec-1", &run).unwrap());
        assert!(!store.save_run("w", "exec-1", &run).unwrap());
        fs::create_dir_all(store.runs_dir().join("w/logs")).unwrap();
        fs::create_dir_all(store.runs_dir().join("mestre/logs")).unwrap();
        let runs = store.runs().unwrap();
        assert_eq!(runs.len(), 1);
        assert_eq!(runs[0].reference, "w/exec-1");
        assert_eq!(store.load_run("w", "exec-1").unwrap().cycle, 1);
        assert!(matches!(
            store.load_run("w", "nao"),
            Err(Error::RunNotFound(_))
        ));
        assert!(store.save_run("..", "x", &run).is_err());
        assert!(store.save_run("w", "a/b", &run).is_err());
    }
}
