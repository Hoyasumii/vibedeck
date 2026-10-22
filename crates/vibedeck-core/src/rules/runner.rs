//! `ShellRunner` e `BuildToolLock` (dados.md §5.2 e §5.4).
//!
//! `$SHELL -lc <comando>` na raiz, stdin `/dev/null`, stdout+stderr no mesmo pipe, timeout com `SIGTERM` no
//! grupo de processos (e nos descendentes achados por `pgrep -P`, se existir), 124 no estouro, 130 no
//! cancelamento, 127 se não lançar.

use std::collections::HashSet;
use std::fs::File;
use std::io::Read;
use std::os::fd::FromRawFd;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use regex::Regex;

pub const TIMED_OUT_STATUS: i32 = 124;
pub const CANCELLED_STATUS: i32 = 130;
/// Depois do `SIGTERM`, quanto esperar antes do `SIGKILL` no grupo (o Swift nunca escalava).
const KILL_GRACE: Duration = Duration::from_secs(5);
/// Depois que o shell termina, quanto esperar o pipe fechar antes de encerrar processos remanescentes.
const PIPE_GRACE: Duration = Duration::from_millis(1000);

// ---- cancelamento ---------------------------------------------------------------------------------

type Handler = Box<dyn Fn() + Send + Sync>;

struct CancelInner {
    cancelled: AtomicBool,
    handlers: Mutex<Vec<(u64, Handler)>>,
    next: AtomicU64,
}

/// Cancela execuções de shell de fora: processos em andamento são encerrados e nenhuma nova começa.
#[derive(Clone)]
pub struct Cancellation(Arc<CancelInner>);

impl Default for Cancellation {
    fn default() -> Self {
        Self::new()
    }
}

impl Cancellation {
    pub fn new() -> Self {
        Cancellation(Arc::new(CancelInner {
            cancelled: AtomicBool::new(false),
            handlers: Mutex::new(Vec::new()),
            next: AtomicU64::new(1),
        }))
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.cancelled.load(Ordering::SeqCst)
    }

    pub fn cancel(&self) {
        if self.0.cancelled.swap(true, Ordering::SeqCst) {
            return;
        }
        let pending = std::mem::take(&mut *lock(&self.0.handlers));
        for (_, handler) in pending {
            handler();
        }
    }

    /// Roda `handler` no cancelamento (já, se já cancelado). Devolve o token para `remove`.
    pub fn on_cancel(&self, handler: impl Fn() + Send + Sync + 'static) -> u64 {
        let id = self.0.next.fetch_add(1, Ordering::SeqCst);
        let handler: Handler = Box::new(handler);
        let run_now = {
            let mut handlers = lock(&self.0.handlers);
            if self.is_cancelled() {
                Some(handler)
            } else {
                handlers.push((id, handler));
                None
            }
        };
        if let Some(handler) = run_now {
            handler();
        }
        id
    }

    pub fn remove(&self, token: u64) {
        lock(&self.0.handlers).retain(|(id, _)| *id != token);
    }
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

// ---- execução -------------------------------------------------------------------------------------

pub struct ShellOptions {
    /// Variáveis somadas ao ambiente atual (`VIBEDECK_ROOT`, `VIBEDECK_FILES`, ...).
    pub env: Vec<(String, String)>,
    pub timeout: Duration,
    /// Caracteres mantidos do fim da saída.
    pub output_limit: usize,
    pub cancellation: Option<Cancellation>,
}

impl Default for ShellOptions {
    fn default() -> Self {
        ShellOptions {
            env: Vec::new(),
            timeout: Duration::from_secs(120),
            output_limit: 20_000,
            cancellation: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellResult {
    pub output: String,
    pub status: i32,
}

fn default_shell() -> &'static str {
    if cfg!(target_os = "macos") {
        "/bin/zsh"
    } else {
        "/bin/sh"
    }
}

/// Um pipe com `FD_CLOEXEC` nas duas pontas (leitura, escrita).
fn make_pipe() -> std::io::Result<(File, File)> {
    let mut fds = [0 as libc::c_int; 2];
    // SAFETY: `fds` tem espaço para dois descritores; os fds devolvidos são nossos e viram `File`.
    unsafe {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        {
            if libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
        #[cfg(not(any(target_os = "linux", target_os = "android")))]
        {
            if libc::pipe(fds.as_mut_ptr()) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            for fd in fds {
                libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC);
            }
        }
        Ok((File::from_raw_fd(fds[0]), File::from_raw_fd(fds[1])))
    }
}

/// Serializa criação do pipe + `spawn`, para um filho de outra thread não herdar a ponta de escrita.
static SPAWN_LOCK: Mutex<()> = Mutex::new(());

fn signal_group(pid: i32, sig: i32) {
    // SAFETY: `killpg`/`kill` só enviam sinais; pid inválido devolve erro, ignorado.
    unsafe {
        libc::killpg(pid, sig);
    }
}

/// `pgrep -P <pid>` (best effort: sem `pgrep`, lista vazia).
fn children(pid: i32) -> Vec<i32> {
    let Ok(out) = Command::new("pgrep")
        .args(["-P", &pid.to_string()])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    else {
        return Vec::new();
    };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .collect()
}

fn descendants(pid: i32, depth: usize) -> Vec<i32> {
    if depth > 16 {
        return Vec::new();
    }
    children(pid)
        .into_iter()
        .flat_map(|c| {
            let mut v = vec![c];
            v.extend(descendants(c, depth + 1));
            v
        })
        .collect()
}

/// `SIGTERM` no shell, no grupo dele e em todos os descendentes (um filho vivo mantém o pipe aberto).
fn terminate_tree(pid: i32) {
    let tree = descendants(pid, 0);
    signal_group(pid, libc::SIGTERM);
    // SAFETY: ver `signal_group`.
    unsafe {
        libc::kill(pid, libc::SIGTERM);
        for p in tree {
            libc::kill(p, libc::SIGTERM);
        }
    }
}

/// Mantém o fim: `"… (saída cortada)\n"` + últimos `limit` caracteres.
fn truncate_tail(text: String, limit: usize) -> String {
    let count = text.chars().count();
    if count <= limit {
        return text;
    }
    let tail: String = text.chars().skip(count - limit).collect();
    format!("… (saída cortada)\n{tail}")
}

/// Roda `command` no shell de login do usuário, com stdout+stderr juntos.
pub fn run_shell(command: &str, root: &Path, opts: &ShellOptions) -> ShellResult {
    let cancellation = opts.cancellation.as_ref();
    if cancellation.is_some_and(Cancellation::is_cancelled) {
        return ShellResult {
            output: "Cancelado.".into(),
            status: CANCELLED_STATUS,
        };
    }
    let shell = std::env::var("SHELL")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| default_shell().to_string());

    let spawned = {
        let _guard = lock(&SPAWN_LOCK);
        make_pipe().and_then(|(reader, writer)| {
            let writer_err = writer.try_clone()?;
            let mut cmd = Command::new(&shell);
            cmd.arg("-lc")
                .arg(command)
                .current_dir(root)
                .stdin(Stdio::null())
                .stdout(Stdio::from(writer))
                .stderr(Stdio::from(writer_err))
                .process_group(0);
            for (k, v) in &opts.env {
                cmd.env(k, v);
            }
            let child = cmd.spawn()?;
            Ok((reader, child))
        })
    };
    let (mut reader, mut child) = match spawned {
        Ok(v) => v,
        Err(e) => {
            return ShellResult {
                output: format!("Não foi possível executar: {e}"),
                status: 127,
            };
        }
    };
    let pid = child.id() as i32;

    let buffer: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
    let reader_done = Arc::new(AtomicBool::new(false));
    {
        let buffer = Arc::clone(&buffer);
        let done = Arc::clone(&reader_done);
        std::thread::spawn(move || {
            let mut chunk = [0u8; 8192];
            loop {
                match reader.read(&mut chunk) {
                    Ok(0) => break,
                    Ok(n) => lock(&buffer).extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                    Err(_) => break,
                }
            }
            done.store(true, Ordering::SeqCst);
        });
    }

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let token = cancellation.map(|c| {
        let flag = Arc::clone(&cancel_flag);
        c.on_cancel(move || flag.store(true, Ordering::SeqCst))
    });

    let started = Instant::now();
    let mut timed_out = false;
    let mut cancelled = false;
    let mut terminated_at: Option<Instant> = None;
    let mut killed = false;
    let exit = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {}
            Err(_) => break None,
        }
        let now = Instant::now();
        if terminated_at.is_none() {
            if cancel_flag.load(Ordering::SeqCst) {
                cancelled = true;
                terminate_tree(pid);
                terminated_at = Some(now);
            } else if now.duration_since(started) >= opts.timeout {
                timed_out = true;
                terminate_tree(pid);
                terminated_at = Some(now);
            }
        } else if !killed && terminated_at.is_some_and(|t| now.duration_since(t) >= KILL_GRACE) {
            signal_group(pid, libc::SIGKILL);
            // SAFETY: ver `signal_group`.
            unsafe {
                libc::kill(pid, libc::SIGKILL);
            }
            killed = true;
        }
        std::thread::sleep(Duration::from_millis(2));
    };
    if let (Some(c), Some(t)) = (cancellation, token) {
        c.remove(t);
    }

    // O shell terminou; se algo ainda segura o pipe (processo em segundo plano), encerra o grupo.
    let drain_start = Instant::now();
    let mut swept = false;
    while !reader_done.load(Ordering::SeqCst) {
        let waited = drain_start.elapsed();
        if !swept && waited >= PIPE_GRACE {
            signal_group(pid, libc::SIGTERM);
            swept = true;
        }
        if waited >= PIPE_GRACE + Duration::from_millis(500) {
            signal_group(pid, libc::SIGKILL);
        }
        if waited >= PIPE_GRACE + Duration::from_millis(1000) {
            break;
        }
        std::thread::sleep(Duration::from_millis(2));
    }

    let bytes = lock(&buffer).clone();
    let text = String::from_utf8_lossy(&bytes).trim().to_string();
    let text = truncate_tail(text, opts.output_limit);
    let join = |text: String, extra: &str| {
        if text.is_empty() {
            extra.to_string()
        } else {
            format!("{text}\n{extra}")
        }
    };
    if cancelled {
        return ShellResult {
            output: join(text, "Cancelado."),
            status: CANCELLED_STATUS,
        };
    }
    if timed_out {
        return ShellResult {
            output: join(
                text,
                &format!("Tempo esgotado ({} s).", opts.timeout.as_secs()),
            ),
            status: TIMED_OUT_STATUS,
        };
    }
    let status = exit
        .map(|s| s.code().or_else(|| s.signal()).unwrap_or(1))
        .unwrap_or(1);
    ShellResult {
        output: if text.is_empty() {
            "(sem saída)".to_string()
        } else {
            text
        },
        status,
    }
}

// ---- trava por ferramenta de build ----------------------------------------------------------------

/// Ferramentas de build cujos scripts compartilham pastas e locks (`.build`, `node_modules`, `target`...):
/// dois scripts com a mesma chave nunca rodam juntos.
pub struct BuildToolLock;

const TOOL_TABLE: &[(&str, &str)] = &[
    (
        "swift",
        r#"\bswift\s+(build|test|run|package)\b|\bxcodebuild\b|\bswiftc\b|\bswift["']\s*,\s*["'](build|test|run|package)\b"#,
    ),
    ("node", r"\b(npm|npx|yarn|pnpm)\s+\S"),
    ("cargo", r"\bcargo\s+\S"),
    ("go", r"\bgo\s+(build|test|run|vet|install|generate|mod)\b"),
    ("gradle", r"(\bgradle|/gradlew)\b"),
    ("maven", r"(\bmvn|/mvnw)\b"),
    ("dotnet", r"\bdotnet\s+\S"),
    ("composer", r"\bcomposer\s+\S|vendor/bin/"),
    ("make", r"\bmake\b(\s|$)"),
];

fn tool_regexes() -> &'static Vec<(&'static str, Regex)> {
    static CELL: std::sync::OnceLock<Vec<(&'static str, Regex)>> = std::sync::OnceLock::new();
    CELL.get_or_init(|| {
        TOOL_TABLE
            .iter()
            .map(|(k, p)| (*k, Regex::new(p).expect("regex da tabela de ferramentas")))
            .collect()
    })
}

fn without_comments(text: &str) -> String {
    text.split('\n')
        .filter(|l| !l.trim_matches([' ', '\t']).starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n")
}

fn reference_regex() -> &'static Regex {
    static CELL: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"[A-Za-z0-9_./-]+\.(?:sh|py)\b").expect("regex de referências"))
}

fn resolve(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| crate::paths::lexical_normalize(path))
}

impl BuildToolLock {
    /// Chaves das ferramentas de build invocadas em `text`. Linhas de comentário são ignoradas.
    pub fn keys_in(text: &str) -> Vec<&'static str> {
        let code = without_comments(text);
        tool_regexes()
            .iter()
            .filter(|(_, re)| re.is_match(&code))
            .map(|(k, _)| *k)
            .collect()
    }

    /// Lê também scripts shell/Python referenciados (wrappers e helpers via `source` podem invocar um build
    /// indireto). Só segue caminhos locais legíveis dentro da raiz; nunca avalia expressões do shell.
    pub fn keys_for_command(command: &str, root: &Path) -> Vec<&'static str> {
        let base = resolve(root);
        let mut text = command.to_string();
        let mut visited: HashSet<PathBuf> = HashSet::new();
        read_references(command, &base, &base, &mut visited, &mut text);
        Self::keys_in(&text)
    }
}

fn read_references(
    source: &str,
    directory: &Path,
    base: &Path,
    visited: &mut HashSet<PathBuf>,
    text: &mut String,
) {
    let code = without_comments(source);
    for m in reference_regex().find_iter(&code) {
        let path = m.as_str();
        let direct = if path.starts_with('/') {
            PathBuf::from(path)
        } else {
            base.join(path)
        };
        let last = Path::new(path)
            .file_name()
            .map(PathBuf::from)
            .unwrap_or_default();
        let candidates = [direct, directory.join(path), directory.join(&last)];
        for candidate in candidates {
            let url = resolve(&candidate);
            if !url.starts_with(base) || url == base {
                continue;
            }
            let Ok(content) = std::fs::read_to_string(&url) else {
                continue;
            };
            if visited.insert(url.clone()) {
                text.push('\n');
                text.push_str(&content);
                let parent = url.parent().unwrap_or(base).to_path_buf();
                read_references(&content, &parent, base, visited, text);
            }
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(timeout_ms: u64) -> ShellOptions {
        ShellOptions {
            timeout: Duration::from_millis(timeout_ms),
            output_limit: 4000,
            ..ShellOptions::default()
        }
    }

    #[test]
    fn exit_codes_and_merged_output() {
        let dir = tempfile::tempdir().unwrap();
        let r = run_shell("echo out; echo err >&2; exit 3", dir.path(), &opts(20_000));
        assert_eq!(r.status, 3);
        assert_eq!(r.output, "out\nerr");
        assert_eq!(
            run_shell("true", dir.path(), &opts(20_000)).output,
            "(sem saída)"
        );
        assert_eq!(run_shell("exit 2", dir.path(), &opts(20_000)).status, 2);
        assert_eq!(
            run_shell("naoexiste-xyz-123", dir.path(), &opts(20_000)).status,
            127
        );
    }

    #[test]
    fn env_cwd_and_stdin() {
        let dir = tempfile::tempdir().unwrap();
        let mut o = opts(20_000);
        o.env = vec![("VIBEDECK_FILES".into(), "a\nb".into())];
        let r = run_shell("pwd; printf '%s' \"$VIBEDECK_FILES\"; cat", dir.path(), &o);
        assert_eq!(r.status, 0);
        let mut lines = r.output.lines();
        let pwd = lines.next().unwrap();
        assert_eq!(
            std::fs::canonicalize(pwd).unwrap(),
            std::fs::canonicalize(dir.path()).unwrap()
        );
        assert_eq!(lines.collect::<Vec<_>>(), ["a", "b"]);
    }

    #[test]
    fn timeout_kills_the_whole_tree() {
        let dir = tempfile::tempdir().unwrap();
        let started = Instant::now();
        let r = run_shell("echo antes; sleep 30; echo depois", dir.path(), &opts(300));
        assert!(started.elapsed() < Duration::from_secs(10));
        assert_eq!(r.status, TIMED_OUT_STATUS);
        assert_eq!(r.output, "antes\nTempo esgotado (0 s).");
    }

    #[test]
    fn timeout_text_counts_seconds() {
        let dir = tempfile::tempdir().unwrap();
        let o = ShellOptions {
            timeout: Duration::from_secs(1),
            ..opts(1000)
        };
        let r = run_shell("sleep 30", dir.path(), &o);
        assert_eq!(r.status, 124);
        assert_eq!(r.output, "Tempo esgotado (1 s).");
    }

    #[test]
    fn output_is_truncated_keeping_the_tail() {
        let dir = tempfile::tempdir().unwrap();
        let r = run_shell(
            "i=0; while [ $i -lt 6000 ]; do printf x; i=$((i+1)); done; printf END",
            dir.path(),
            &opts(20_000),
        );
        assert!(r.output.starts_with("… (saída cortada)\n"));
        assert!(r.output.ends_with("xxxEND"));
        assert_eq!(
            r.output.chars().count(),
            "… (saída cortada)\n".chars().count() + 4000
        );
    }

    #[test]
    fn cancellation_before_and_during() {
        let dir = tempfile::tempdir().unwrap();
        let c = Cancellation::new();
        c.cancel();
        let o = ShellOptions {
            cancellation: Some(c),
            ..opts(20_000)
        };
        let r = run_shell("echo nunca", dir.path(), &o);
        assert_eq!((r.output.as_str(), r.status), ("Cancelado.", 130));

        let c = Cancellation::new();
        let o = ShellOptions {
            cancellation: Some(c.clone()),
            ..opts(60_000)
        };
        let handle = {
            let root = dir.path().to_path_buf();
            std::thread::spawn(move || run_shell("echo rodando; sleep 30", &root, &o))
        };
        std::thread::sleep(Duration::from_millis(400));
        c.cancel();
        let r = handle.join().unwrap();
        assert_eq!(r.status, 130);
        assert_eq!(r.output, "rodando\nCancelado.");
    }

    #[test]
    fn background_process_does_not_hang_the_reader() {
        let dir = tempfile::tempdir().unwrap();
        let started = Instant::now();
        let r = run_shell("echo oi; sleep 30 &", dir.path(), &opts(20_000));
        assert!(started.elapsed() < Duration::from_secs(10));
        assert_eq!(r.status, 0);
        assert_eq!(r.output, "oi");
    }

    #[test]
    fn concurrent_outputs_stay_separate() {
        let dir = tempfile::tempdir().unwrap();
        std::thread::scope(|s| {
            let handles: Vec<_> = (0..8)
                .map(|i| {
                    let root = dir.path();
                    s.spawn(move || {
                        let r = run_shell(&format!("echo job{i}"), root, &opts(20_000));
                        (i, r)
                    })
                })
                .collect();
            for h in handles {
                let (i, r) = h.join().unwrap();
                assert_eq!(r.output, format!("job{i}"));
            }
        });
    }

    #[test]
    fn build_tool_detection() {
        assert_eq!(BuildToolLock::keys_in("swift build -c release"), ["swift"]);
        assert_eq!(
            BuildToolLock::keys_in("cargo test && npm run x"),
            ["node", "cargo"]
        );
        assert_eq!(
            BuildToolLock::keys_in("# cargo build\necho oi"),
            Vec::<&str>::new()
        );
        assert_eq!(BuildToolLock::keys_in("go test ./..."), ["go"]);
        assert_eq!(BuildToolLock::keys_in("./gradlew build"), ["gradle"]);
        assert_eq!(BuildToolLock::keys_in("make"), ["make"]);
        assert_eq!(BuildToolLock::keys_in("make -j4"), ["make"]);
        assert_eq!(BuildToolLock::keys_in("mvn package"), ["maven"]);
        assert_eq!(BuildToolLock::keys_in("dotnet build"), ["dotnet"]);
        assert_eq!(BuildToolLock::keys_in("composer install"), ["composer"]);
        assert_eq!(BuildToolLock::keys_in("echo makefile"), Vec::<&str>::new());
    }

    #[test]
    fn build_tool_detection_follows_wrappers_without_looping() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("t")).unwrap();
        std::fs::write(root.join("t/a.sh"), "#!/bin/sh\n. t/b.sh\n").unwrap();
        std::fs::write(root.join("t/b.sh"), "cargo build\n. t/a.sh\n").unwrap();
        assert_eq!(BuildToolLock::keys_for_command("t/a.sh", root), ["cargo"]);
        // referência por nome relativo ao diretório do script
        std::fs::write(root.join("t/c.sh"), "bash helper.sh\n").unwrap();
        std::fs::write(root.join("t/helper.sh"), "npm test\n").unwrap();
        assert_eq!(BuildToolLock::keys_for_command("t/c.sh", root), ["node"]);
        // python e caminhos fora da raiz
        std::fs::write(root.join("t/p.py"), "subprocess.run(['swift', 'build'])\n").unwrap();
        assert_eq!(
            BuildToolLock::keys_for_command("python3 t/p.py", root),
            ["swift"]
        );
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(outside.path().join("x.sh"), "cargo build\n").unwrap();
        let cmd = format!("{}", outside.path().join("x.sh").display());
        assert!(BuildToolLock::keys_for_command(&cmd, root).is_empty());
    }
}
