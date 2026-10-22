//! Integração: `vibedeck mcp --app` pelo binário real (tools do app, progresso, cancelamento, notificações).

use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

static COUNTER: AtomicUsize = AtomicUsize::new(0);
const WAIT: Duration = Duration::from_secs(30);

struct Project(PathBuf);

impl Project {
    fn new() -> Self {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("vibedeck-app-it-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("vibedeck.json"), "{\"name\":\"t\"}").unwrap();
        Project(dir)
    }

    fn path(&self, rel: &str) -> PathBuf {
        self.0.join(rel)
    }

    fn app(&self) -> Session {
        Session::start(&self.0, &["mcp", "--app"], &[])
    }

    fn app_with_env(&self, env: &[(&str, &str)]) -> Session {
        Session::start(&self.0, &["mcp", "--app"], env)
    }

    fn plain(&self) -> Session {
        Session::start(&self.0, &["mcp"], &[])
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct Session {
    child: Child,
    stdin: Option<ChildStdin>,
    lines: Receiver<Value>,
    notes: Vec<Value>,
    next_id: i64,
    init: Value,
}

impl Session {
    fn start(dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Self {
        let support = dir.join(".app-support");
        let mut child = Command::new(env!("CARGO_BIN_EXE_vibedeck"))
            .args(args)
            .current_dir(dir)
            .env("VIBEDECK_APP_SUPPORT", &support)
            .envs(env.iter().copied())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().unwrap();
        let (tx, lines) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                let value: Value = serde_json::from_str(&line).expect("stdout só tem JSON-RPC");
                if tx.send(value).is_err() {
                    break;
                }
            }
        });
        let mut session = Session {
            child,
            stdin,
            lines,
            notes: Vec::new(),
            next_id: 1,
            init: Value::Null,
        };
        session.init = session.request(
            "initialize",
            json!({"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}),
        );
        session.send(&json!({"jsonrpc":"2.0","method":"notifications/initialized"}));
        session
    }

    fn send(&mut self, message: &Value) {
        let stdin = self.stdin.as_mut().unwrap();
        writeln!(stdin, "{message}").unwrap();
        stdin.flush().unwrap();
    }

    /// Envia uma requisição e devolve o `result` (ou `error`), guardando as notificações que chegarem antes.
    fn request(&mut self, method: &str, params: Value) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        self.send(&json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}));
        self.reply(id)
    }

    fn reply(&mut self, id: i64) -> Value {
        let deadline = Instant::now() + WAIT;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            let message = self.lines.recv_timeout(left).expect("resposta a tempo");
            if message["id"] == id {
                return if message.get("error").is_some() {
                    message["error"].clone()
                } else {
                    message["result"].clone()
                };
            }
            self.notes.push(message);
        }
    }

    fn call(&mut self, name: &str, arguments: Value) -> (bool, String) {
        let result = self.request("tools/call", json!({"name":name,"arguments":arguments}));
        (
            result["isError"].as_bool().unwrap_or(false),
            result["content"][0]["text"]
                .as_str()
                .unwrap_or("")
                .to_string(),
        )
    }

    fn ok(&mut self, name: &str, arguments: Value) -> String {
        let (is_error, text) = self.call(name, arguments);
        assert!(!is_error, "{name} falhou: {text}");
        text
    }

    fn fail(&mut self, name: &str, arguments: Value) -> String {
        let (is_error, text) = self.call(name, arguments);
        assert!(is_error, "{name} deveria falhar, devolveu: {text}");
        text
    }

    fn json(&mut self, name: &str, arguments: Value) -> Value {
        serde_json::from_str(&self.ok(name, arguments)).expect("resultado JSON")
    }

    /// Espera uma notificação `method` (já recebida ou nova).
    fn note(&mut self, method: &str, within: Duration) -> Option<Value> {
        if let Some(at) = self.notes.iter().position(|n| n["method"] == method) {
            return Some(self.notes.remove(at));
        }
        let deadline = Instant::now() + within;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.lines.recv_timeout(left) {
                Ok(message) if message["method"] == method => return Some(message),
                Ok(message) => self.notes.push(message),
                Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => return None,
            }
        }
    }

    fn tool_names(&mut self) -> Vec<String> {
        self.request("tools/list", Value::Null)["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap().to_string())
            .collect()
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.stdin.take();
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

const APP_ONLY: [&str; 18] = [
    "release_orphaned",
    "workflow_run_restart",
    "put_record",
    "delete_record",
    "put_project",
    "list_checks",
    "delete_doc",
    "workflow_run_delete",
    "workflow_run_checkpoint",
    "workflow_run_save_output",
    "workflow_run_resume",
    "import_attachment",
    "rule_verification_status",
    "project_revision",
    "reorganize_restore",
    "idea_implement",
    "idea_run",
    "ai_usage_record",
];

#[test]
fn sem_app_o_catalogo_e_as_capabilities_nao_mudam() {
    let p = Project::new();
    let mut plain = p.plain();
    let names = plain.tool_names();
    for name in APP_ONLY.iter() {
        assert!(!names.contains(&name.to_string()), "{name} vazou sem --app");
    }
    assert_eq!(names.len(), 99, "catálogo padrão: 99 tools");
    let caps = &plain.init["capabilities"]["resources"];
    assert_eq!(
        (caps["subscribe"].clone(), caps["listChanged"].clone()),
        (json!(false), json!(false))
    );
    // sem --app, author é ignorado (sempre ai) e não está no schema
    let tools = plain.request("tools/list", Value::Null);
    let add_idea = tools["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["name"] == "add_idea")
        .unwrap();
    assert!(
        add_idea["inputSchema"]["properties"]
            .get("author")
            .is_none()
    );
    let created: Value =
        serde_json::from_str(&plain.ok("add_idea", json!({"title":"I","author":"human"}))).unwrap();
    assert_eq!(created["author"], "ai");
    // sem --app, progressToken não gera notificação
    assert!(
        plain
            .note("notifications/progress", Duration::from_millis(100))
            .is_none()
    );
}

#[test]
fn serve_com_app_tambem_funciona_como_subcomando() {
    let p = Project::new();
    let mut s = Session::start(&p.0, &["mcp", "serve", "--app"], &[]);
    assert_eq!(s.init["capabilities"]["resources"]["listChanged"], true);
    assert!(s.tool_names().contains(&"put_record".to_string()));
}

#[test]
fn com_app_o_catalogo_ganha_as_tools_extras_e_author() {
    let p = Project::new();
    let mut app = p.app();
    let names = app.tool_names();
    for name in APP_ONLY.iter() {
        assert!(
            names.contains(&name.to_string()),
            "{name} ausente com --app"
        );
    }
    let unique: std::collections::HashSet<_> = names.iter().collect();
    assert_eq!(unique.len(), names.len(), "nomes de tool repetidos");
    let caps = &app.init["capabilities"]["resources"];
    assert_eq!(
        (caps["subscribe"].clone(), caps["listChanged"].clone()),
        (json!(true), json!(true))
    );
    let tools = app.request("tools/list", Value::Null);
    for name in [
        "add_review_item",
        "add_rule",
        "add_idea",
        "add_idea_rule",
        "add_stack",
        "add_pattern",
        "add_kit",
        "add_agent",
        "add_command",
        "add_skill",
        "add_workflow",
    ] {
        let tool = tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["name"] == name)
            .unwrap();
        assert_eq!(
            tool["inputSchema"]["properties"]["author"]["enum"],
            json!(["human", "ai"]),
            "{name}"
        );
    }
    let list_docs = tools["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|t| t["name"] == "list_docs")
        .count();
    assert_eq!(list_docs, 1, "list_docs do app substitui o padrão");
}

#[test]
fn author_human_ou_ai_nas_tools_de_criacao() {
    let p = Project::new();
    let mut app = p.app();
    let idea = app.json("add_idea", json!({"title":"Humana","author":"human"}));
    assert_eq!(idea["author"], "human");
    let idea = app.json("add_idea", json!({"title":"Padrão"}));
    assert_eq!(idea["author"], "ai");
    let rule = app.json(
        "add_rule",
        json!({"topic":"Geral","text":"Faça X","author":"human"}),
    );
    let file = p.path(&format!(
        ".vibedeck/rules/{}.json",
        rule["topic"].as_str().unwrap()
    ));
    let topic: Value = serde_json::from_str(&std::fs::read_to_string(file).unwrap()).unwrap();
    assert_eq!(topic["rules"][0]["author"], "human");
    let item = app.json(
        "add_review_item",
        json!({"group":"G","kind":"fix","title":"Item","author":"human"}),
    );
    assert_eq!(item["item"]["author"], "human");
    let agent = app.json("add_agent", json!({"title":"Ag","author":"human"}));
    assert_eq!(agent["author"], "human");
    let flow = app.json("add_workflow", json!({"title":"Fl","author":"human"}));
    assert_eq!(flow["author"], "human");
    assert!(
        app.fail("add_idea", json!({"title":"X","author":"robo"}))
            .contains("author")
    );
}

#[test]
fn put_record_e_delete_record() {
    let p = Project::new();
    let mut app = p.app();
    let record = json!({
        "$schema": "https://vibedeck.app/schema/v1/idea.schema.json",
        "id": "11111111-2222-3333-4444-555555555555",
        "title": "Ideia do app",
        "status": "new",
        "rules": [],
        "author": "human",
        "createdAt": "2026-01-02T03:04:05Z",
        "updatedAt": "2026-01-02T03:04:05Z"
    });
    assert_eq!(
        app.ok(
            "put_record",
            json!({"kind":"ideas","slug":"grupo/sub/ideia","record": record.to_string()})
        ),
        "Salvo: grupo/sub/ideia"
    );
    let file = p.path(".vibedeck/ideas/grupo/sub/ideia.json");
    let saved: Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
    assert_eq!(saved["author"], "human");
    assert_eq!(saved["id"], "11111111-2222-3333-4444-555555555555");
    let got = app.json("get_idea", json!({"idea":"grupo/sub/ideia"}));
    assert_eq!(got["title"], "Ideia do app");

    // também aceita o registro como objeto
    app.ok(
        "put_record",
        json!({"kind":"ideas","slug":"outra","record": record}),
    );
    assert!(p.path(".vibedeck/ideas/outra.json").is_file());

    assert!(
        app.fail(
            "put_record",
            json!({"kind":"docs","slug":"x","record":"{}"})
        )
        .contains("Tipo de registro")
    );
    assert!(
        app.fail(
            "put_record",
            json!({"kind":"rules","slug":"x","record":"{"})
        )
        .contains("Registro inválido")
    );
    assert!(
        app.fail(
            "put_record",
            json!({"kind":"rules","slug":"../x","record":"{\"title\":\"T\"}"})
        )
        .contains("inválido")
    );
    assert!(!p.path(".vibedeck/rules/x.json").exists());

    assert_eq!(
        app.ok(
            "delete_record",
            json!({"kind":"ideas","slug":"grupo/sub/ideia"})
        ),
        "Removido: grupo/sub/ideia"
    );
    assert!(!file.exists());
    let trash: Vec<_> = walk(&p.path(".vibedeck/.trash"));
    assert_eq!(trash.len(), 1);
    assert!(
        trash[0].ends_with("ideas/grupo/sub/ideia.json"),
        "{trash:?}"
    );
    assert!(
        app.fail(
            "delete_record",
            json!({"kind":"ideas","slug":"grupo/sub/ideia"})
        )
        .contains("não encontrada")
    );
}

fn walk(dir: &Path) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                out.extend(walk(&path));
            } else {
                out.push(path.to_string_lossy().into_owned());
            }
        }
    }
    out
}

#[test]
fn delete_record_de_regras_solta_a_ideia_promovida() {
    let p = Project::new();
    let mut app = p.app();
    let idea = app.json("add_idea", json!({"title":"Com regras"}));
    let slug = idea["slug"].as_str().unwrap().to_string();
    app.ok(
        "add_idea_rule",
        json!({"idea": slug, "text":"Regra da ideia"}),
    );
    let promoted = app.ok("promote_idea", json!({"idea": slug}));
    let topic = promoted
        .lines()
        .next()
        .unwrap()
        .rsplit(": ")
        .next()
        .unwrap()
        .to_string();
    assert_eq!(
        app.ok("delete_record", json!({"kind":"rules","slug":topic})),
        format!("Removido: {topic}")
    );
    let after = app.json("get_idea", json!({"idea": slug}));
    assert!(after.get("promotedTopic").is_none(), "{after}");
}

#[test]
fn put_project_grava_e_avisa_quando_o_readme_nao_atualiza() {
    let p = Project::new();
    let mut app = p.app_with_env(&[("VIBEDECK_SKILL_ICONS_URL", "http://127.0.0.1:9/mcp")]);
    let plain = app.ok(
        "put_project",
        json!({"project": json!({"name":"Renomeado"}).to_string()}),
    );
    assert_eq!(plain, "Salvo: vibedeck.json");
    let project: Value =
        serde_json::from_str(&std::fs::read_to_string(p.path("vibedeck.json")).unwrap()).unwrap();
    assert_eq!(project["name"], "Renomeado");

    let with_stack = json!({"name":"Renomeado","stack":[{"icon":"rust","name":"Rust"}]});
    let text = app.ok("put_project", json!({"project": with_stack.to_string()}));
    assert!(text.starts_with("Salvo: vibedeck.json\nAviso:"), "{text}");
    let project: Value =
        serde_json::from_str(&std::fs::read_to_string(p.path("vibedeck.json")).unwrap()).unwrap();
    assert_eq!(
        project["stack"][0]["icon"], "rust",
        "o projeto fica salvo mesmo sem README"
    );
    assert!(
        app.fail("put_project", json!({"project": "{"}))
            .contains("Projeto inválido")
    );
}

#[test]
fn docs_modified_delete_doc_e_anexo() {
    let p = Project::new();
    let mut app = p.app();
    app.ok(
        "write_doc",
        json!({"title":"Guia","content":"# Guia\n\ncorpo"}),
    );
    let rows = app.json("list_docs", json!({}));
    assert_eq!(rows[0]["slug"], "guia");
    let modified = rows[0]["modified"].as_str().unwrap();
    assert!(
        modified.ends_with('Z') && modified.len() == 20,
        "{modified}"
    );
    assert_eq!(rows[0]["group"], "");

    let data = "iVBORw0KGgo="; // bytes quaisquer em base64
    let link = app.ok(
        "import_attachment",
        json!({"owner":"guia","name":"Captura.png","data_base64":data}),
    );
    assert!(
        link.starts_with("![Captura.png](../attachments/guia-captura"),
        "{link}"
    );
    let files = walk(&p.path(".vibedeck/attachments"));
    assert_eq!(files.len(), 1);
    assert_eq!(
        std::fs::read(&files[0]).unwrap(),
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    );
    assert!(
        app.fail(
            "import_attachment",
            json!({"owner":"guia","name":"a.png","data_base64":"@@@"})
        )
        .contains("base64")
    );

    assert_eq!(
        app.ok("delete_doc", json!({"slug":"guia"})),
        "Removido: guia"
    );
    assert!(!p.path(".vibedeck/docs/guia.md").exists());
    assert!(walk(&p.path(".vibedeck/.trash"))[0].ends_with("docs/guia.md"));
    assert_eq!(app.json("list_docs", json!({})), json!([]));
    assert!(
        app.fail("delete_doc", json!({"slug":"guia"}))
            .contains("guia")
    );
}

#[test]
fn item_groups_move_item_aceita_raiz_com_barra() {
    let p = Project::new();
    let mut app = p.app();
    let created = app.json(
        "add_idea",
        json!({"title":"Mover","reference":"grupo/mover"}),
    );
    assert_eq!(created["slug"], "grupo/mover");
    app.ok(
        "item_groups",
        json!({"concept":"ideas","action":"move_item","reference":"grupo/mover","to":"/"}),
    );
    assert!(p.path(".vibedeck/ideas/mover.json").is_file());
    assert!(!p.path(".vibedeck/ideas/grupo/mover.json").exists());
    app.ok(
        "item_groups",
        json!({"concept":"ideas","action":"move_item","reference":"mover","to":"outro"}),
    );
    assert!(p.path(".vibedeck/ideas/outro/mover.json").is_file());
}

fn workflow(app: &mut Session) -> String {
    let agent = app.json("add_agent", json!({"title":"Dev"}));
    let flow = app.json("add_workflow", json!({"title":"Fluxo"}));
    let slug = flow["slug"].as_str().unwrap().to_string();
    app.ok(
        "add_workflow_step",
        json!({"workflow": slug, "target": agent["slug"]}),
    );
    slug
}

#[test]
fn execucoes_de_workflow_checkpoint_saida_resume_e_delete() {
    let p = Project::new();
    let mut app = p.app();
    let flow = workflow(&mut app);
    let started = app.json(
        "workflow_run_start",
        json!({"workflow": flow, "input":"tarefa"}),
    );
    let reference = started["ref"].as_str().unwrap().to_string();
    let shown = app.json("workflow_run_show", json!({"run": reference}));
    let step = shown["current"].as_str().unwrap().to_string();

    assert_eq!(
        app.ok(
            "workflow_run_checkpoint",
            json!({"run": reference, "step": step, "output":"parcial","completed":false})
        ),
        format!("Salvo: {reference}")
    );
    let shown = app.json("workflow_run_show", json!({"run": reference}));
    assert_eq!(shown["checkpoint"]["output"], "parcial");
    assert_eq!(shown["checkpoint"]["completed"], false);
    assert!(
        app.fail(
            "workflow_run_checkpoint",
            json!({"run": reference, "step":"nao-e-esta","output":"x"})
        )
        .contains("transição")
    );

    let note = app.ok(
        "workflow_run_save_output",
        json!({"run": reference, "output":"saída completa"}),
    );
    assert!(
        note.contains("outputs/") && note.contains("14 caracteres"),
        "{note}"
    );
    let outputs = walk(&p.path(&format!(".vibedeck/runs/{reference}/outputs")));
    assert_eq!(
        std::fs::read_to_string(&outputs[0]).unwrap(),
        "saída completa"
    );

    app.ok(
        "workflow_run_stop",
        json!({"run": reference, "reason":"pausa"}),
    );
    let resumed = app.json("workflow_run_resume", json!({"run": reference}));
    assert_eq!(resumed["ref"], reference.as_str());
    assert_eq!(resumed["run"]["status"], "running");
    let restarted = app.json("workflow_run_restart", json!({"run": reference}));
    assert_eq!(restarted["run"]["cycle"], 2);
    assert_eq!(restarted["run"]["current"], step.as_str());
    assert_eq!(restarted["run"]["status"], "running");

    assert_eq!(
        app.ok("workflow_run_delete", json!({"run": reference})),
        format!("Removido: {reference}")
    );
    assert!(!p.path(&format!(".vibedeck/runs/{reference}")).exists());
    assert!(
        app.fail("workflow_run_delete", json!({"run": reference}))
            .contains("não encontrada")
    );
}

#[test]
fn ideia_como_pedido_de_implementacao_e_execucao() {
    let p = Project::new();
    let mut app = p.app();
    let flow = workflow(&mut app);
    let idea = app.json("add_idea", json!({"title":"Implementável"}));
    let slug = idea["slug"].as_str().unwrap().to_string();
    assert_eq!(
        app.ok("idea_run", json!({"idea": slug, "workflow": flow})),
        "null"
    );
    assert!(
        app.fail("idea_implement", json!({"idea": slug, "workflow": flow}))
            .contains("aprovada")
    );

    // ideia aprovada e viável gravada pelo app (put_record), com a impressão digital atual
    let mut record = app.json("get_idea", json!({"idea": slug}));
    record["status"] = json!("approved");
    record["rules"] = json!([{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","text":"Teste","severity":"must","author":"ai","createdAt":"2026-01-01T00:00:00Z"}]);
    record["readiness"] =
        json!({"viable": true, "checkedAt":"2026-01-01T00:00:00Z", "fingerprint": "x"});
    app.ok(
        "put_record",
        json!({"kind":"ideas","slug": slug, "record": record}),
    );
    // impressão digital desatualizada: não é elegível
    assert!(
        app.fail("idea_implement", json!({"idea": slug}))
            .contains("aprovada")
    );

    // avaliação atual: a ideia vira pedido de implementação, com a execução ligada a ela
    use vibedeck_core::ideas::IdeaFingerprint;
    let idea: vibedeck_core::model::Idea = serde_json::from_value(record.clone()).unwrap();
    record["readiness"]["fingerprint"] = json!(idea.content_fingerprint());
    app.ok(
        "put_record",
        json!({"kind":"ideas","slug": slug, "record": record}),
    );
    let started = app.json("idea_implement", json!({"idea": slug, "workflow": flow}));
    let run_ref = started["run_ref"].as_str().unwrap().to_string();
    assert!(run_ref.starts_with(&format!("{flow}/")));
    assert!(
        started["prompt"]
            .as_str()
            .unwrap()
            .contains("Implementável")
    );
    assert_eq!(started["run"]["status"], "running");
    let topic = started["topic"].as_str().unwrap().to_string();
    assert!(p.path(&format!(".vibedeck/rules/{topic}.json")).is_file());
    let found = app.json("idea_run", json!({"idea": slug, "workflow": flow}));
    assert_eq!(found["ref"], run_ref.as_str());
    let again = app.json(
        "idea_implement",
        json!({"idea": slug, "workflow": flow, "restart": true}),
    );
    assert_eq!(again["run_ref"], run_ref.as_str());
    assert_eq!(again["run"]["cycle"], 2);
    let plain = app.json("idea_implement", json!({"idea": slug}));
    assert!(plain["run_ref"].is_null());
}

#[test]
fn rule_verification_status_e_list_checks() {
    let p = Project::new();
    let mut app = p.app();
    assert_eq!(app.json("list_checks", json!({})), json!([]));
    let rule = app.json(
        "add_rule",
        json!({"topic":"Geral","text":"Sempre X","author":"human"}),
    );
    let topic = rule["topic"].as_str().unwrap().to_string();
    app.ok(
        "set_rule_test",
        json!({"rule_id": rule["ruleId"], "mode":"script","command":"exit 0"}),
    );
    let item = app.json(
        "add_review_item",
        json!({"group":"G","kind":"fix","title":"Item"}),
    );
    let id = item["item"]["id"].as_str().unwrap().to_string();

    let status = app.json("rule_verification_status", json!({"review_item": id}));
    assert_eq!(status["required_topics"], json!([topic]));
    assert!(
        status["problems"][0]
            .as_str()
            .unwrap()
            .contains("Nenhum check registrado"),
        "{status}"
    );

    app.ok(
        "submit_rule_check",
        json!({"task":"feito","review_item": id}),
    );
    let status = app.json("rule_verification_status", json!({"review_item": id}));
    assert_eq!(status["problems"], json!([]), "{status}");
    let checks = app.json("list_checks", json!({}));
    assert_eq!(checks.as_array().unwrap().len(), 1);
    assert_eq!(checks[0]["passed"], true);
    assert_eq!(checks[0]["task"], "feito");
    assert!(
        app.fail(
            "rule_verification_status",
            json!({"review_item":"inexistente"})
        )
        .contains("não encontrado")
    );
}

fn progress_notes(app: &mut Session, token: impl Into<Value>) -> Vec<Value> {
    let token = token.into();
    let mut notes = Vec::new();
    while let Some(note) = app.note("notifications/progress", Duration::from_millis(200)) {
        if note["params"]["progressToken"] == token {
            notes.push(note);
        }
    }
    notes
}

#[test]
fn progresso_por_script_em_run_rule_tests_e_submit_rule_check() {
    let p = Project::new();
    let mut app = p.app();
    let ok = app.json(
        "add_rule",
        json!({"topic":"Prog","text":"Passa","author":"human"}),
    );
    let bad = app.json(
        "add_rule",
        json!({"topic":"Prog","text":"Falha","author":"human"}),
    );
    app.ok(
        "set_rule_test",
        json!({"rule_id": ok["ruleId"], "mode":"script","command":"echo bom; exit 0"}),
    );
    app.ok(
        "set_rule_test",
        json!({"rule_id": bad["ruleId"], "mode":"script","command":"echo ruim; exit 3"}),
    );

    let result = app.request(
        "tools/call",
        json!({"name":"run_rule_tests","arguments":{"topics":["prog"]},"_meta":{"progressToken":"tok-1"}}),
    );
    assert_eq!(result["isError"], false);
    let rows: Value = serde_json::from_str(result["content"][0]["text"].as_str().unwrap()).unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 2);
    let notes = progress_notes(&mut app, "tok-1");
    assert_eq!(notes.len(), 4, "running+resultado por script: {notes:?}");
    let mut last = 0;
    for note in &notes {
        let progress = note["params"]["progress"].as_u64().unwrap();
        assert!(progress > last, "progress cresce");
        last = progress;
    }
    let detail = |rule: &Value, state: &str| {
        notes
            .iter()
            .map(|n| &n["params"])
            .find(|p| p["ruleId"] == *rule && p["state"] == state)
            .cloned()
    };
    assert!(detail(&ok["ruleId"], "running").is_some());
    let pass = detail(&ok["ruleId"], "pass").expect("pass");
    assert!(pass["output"].as_str().unwrap().contains("bom"));
    let fail = detail(&bad["ruleId"], "fail").expect("fail");
    assert!(fail["output"].as_str().unwrap().contains("ruim"));
    let message: Value = serde_json::from_str(fail["message"].as_str().unwrap()).unwrap();
    assert_eq!(message["state"], "fail");
    assert_eq!(message["ruleId"], bad["ruleId"]);

    let result = app.request(
        "tools/call",
        json!({"name":"submit_rule_check","arguments":{"task":"t","topics":["prog"]},"_meta":{"progressToken":7}}),
    );
    assert_eq!(result["isError"], false);
    assert_eq!(progress_notes(&mut app, 7).len(), 4);

    // sem progressToken nada é emitido
    app.ok("run_rule_tests", json!({"topics":["prog"]}));
    assert!(
        app.note("notifications/progress", Duration::from_millis(300))
            .is_none()
    );
}

#[test]
fn cancelamento_interrompe_a_execucao_de_scripts() {
    let p = Project::new();
    let mut app = p.app();
    let slow = app.json(
        "add_rule",
        json!({"topic":"Lento","text":"Demora","author":"human"}),
    );
    app.ok(
        "set_rule_test",
        json!({"rule_id": slow["ruleId"], "mode":"script","command":"sleep 60"}),
    );

    let id = 900;
    app.send(&json!({"jsonrpc":"2.0","id":id,"method":"tools/call","params":{
        "name":"run_rule_tests","arguments":{"topics":["lento"]},"_meta":{"progressToken":"slow"}}}));
    let running = app
        .note("notifications/progress", WAIT)
        .expect("script começou");
    assert_eq!(running["params"]["state"], "running");
    let start = Instant::now();
    app.send(&json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":id,"reason":"usuário"}}));
    let reply = app.reply(id);
    assert!(
        start.elapsed() < Duration::from_secs(20),
        "cancelou sem esperar o sleep"
    );
    assert_eq!(reply["isError"], true);
    assert!(
        reply["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("cancelada"),
        "{reply}"
    );

    // a conexão segue viva e uma nova chamada não herda o cancelamento
    app.ok(
        "set_rule_test",
        json!({"rule_id": slow["ruleId"], "mode":"script","command":"exit 0"}),
    );
    let rows = app.json("run_rule_tests", json!({"topics":["lento"]}));
    assert_eq!(rows[0]["verdict"], "pass");
}

#[test]
fn cancelar_submit_rule_check_nao_grava_check() {
    let p = Project::new();
    let mut app = p.app();
    let slow = app.json(
        "add_rule",
        json!({"topic":"Lento","text":"Demora","author":"human"}),
    );
    app.ok(
        "set_rule_test",
        json!({"rule_id": slow["ruleId"], "mode":"script","command":"sleep 60"}),
    );
    let id = 901;
    app.send(&json!({"jsonrpc":"2.0","id":id,"method":"tools/call","params":{
        "name":"submit_rule_check","arguments":{"task":"t","topics":["lento"]},"_meta":{"progressToken":"s2"}}}));
    app.note("notifications/progress", WAIT)
        .expect("script começou");
    app.send(
        &json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":id}}),
    );
    let reply = app.reply(id);
    assert_eq!(reply["isError"], true);
    assert_eq!(app.json("list_checks", json!({})), json!([]));
}

#[test]
fn cancelamento_chegando_antes_da_chamada_comecar_vale() {
    let p = Project::new();
    let mut app = p.app();
    let slow = app.json(
        "add_rule",
        json!({"topic":"Lento","text":"Demora","author":"human"}),
    );
    app.ok(
        "set_rule_test",
        json!({"rule_id": slow["ruleId"], "mode":"script","command":"sleep 60"}),
    );
    // a primeira fica ocupada; a segunda é cancelada ainda na fila
    app.send(
        &json!({"jsonrpc":"2.0","id":910,"method":"tools/call","params":{
        "name":"run_rule_tests","arguments":{"topics":["lento"]},"_meta":{"progressToken":"a"}}}),
    );
    app.note("notifications/progress", WAIT)
        .expect("primeira começou");
    app.send(
        &json!({"jsonrpc":"2.0","id":911,"method":"tools/call","params":{
        "name":"run_rule_tests","arguments":{"topics":["lento"]}}}),
    );
    app.send(
        &json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":911}}),
    );
    app.send(
        &json!({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":910}}),
    );
    let first = app.reply(910);
    assert_eq!(first["isError"], true);
    let second = app.reply(911);
    assert_eq!(second["isError"], true);
    assert!(
        second["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("cancelada")
    );
}

#[test]
fn project_revision_e_notificacao_de_lista_alterada() {
    let p = Project::new();
    let mut app = p.app();
    let first = app.json("project_revision", json!({}));
    let again = app.json("project_revision", json!({}));
    assert_eq!(first, again);
    assert_eq!(first["revision"].as_str().unwrap().len(), 64);

    app.request("resources/subscribe", json!({"uri":"vibedeck://project"}));
    std::fs::create_dir_all(p.path(".vibedeck/ideas")).unwrap();
    std::fs::write(
        p.path(".vibedeck/ideas/externa.json"),
        "{\"title\":\"Externa\"}",
    )
    .unwrap();
    assert!(
        app.note(
            "notifications/resources/list_changed",
            Duration::from_secs(10)
        )
        .is_some(),
        "mudança em .vibedeck/ notifica"
    );
    let updated = app
        .note("notifications/resources/updated", Duration::from_secs(2))
        .expect("updated da URI assinada");
    assert_eq!(updated["params"]["uri"], "vibedeck://project");
    let second = app.json("project_revision", json!({}));
    assert_ne!(first, second);

    // mudar vibedeck.json também notifica
    std::fs::write(p.path("vibedeck.json"), "{\"name\":\"outro nome\"}").unwrap();
    assert!(
        app.note(
            "notifications/resources/list_changed",
            Duration::from_secs(10)
        )
        .is_some()
    );

    // quieto: nada novo
    assert!(
        app.note(
            "notifications/resources/list_changed",
            Duration::from_millis(2500)
        )
        .is_none()
    );

    app.request("resources/unsubscribe", json!({"uri":"vibedeck://project"}));
    assert!(
        app.request("resources/subscribe", json!({}))
            .get("message")
            .is_some(),
        "uri é obrigatória"
    );
}

#[test]
fn sem_app_nao_ha_notificacoes_nem_subscribe() {
    let p = Project::new();
    let mut plain = p.plain();
    std::fs::write(p.path(".vibedeck-nada"), "x").unwrap();
    let denied = plain.request("resources/subscribe", json!({"uri":"vibedeck://project"}));
    assert_eq!(denied["code"], -32601);
    std::fs::create_dir_all(p.path(".vibedeck/ideas")).unwrap();
    std::fs::write(p.path(".vibedeck/ideas/x.json"), "{\"title\":\"X\"}").unwrap();
    assert!(
        plain
            .note(
                "notifications/resources/list_changed",
                Duration::from_millis(2500)
            )
            .is_none()
    );
}

#[test]
fn ai_usage_record_aparece_em_ai_usage() {
    let p = Project::new();
    let mut app = p.app();
    let record = json!({
        "id": "AAAAAAAA-0000-0000-0000-000000000001",
        "taskID": "AAAAAAAA-0000-0000-0000-000000000002",
        "operation": "chat",
        "provider": "claude",
        "startedAt": "2026-01-01T00:00:00Z",
        "duration": 1.5,
        "attempt": 1,
        "status": "completed",
        "promptCharacters": 42,
        "tokens": {"input": 10, "output": 5},
        "coverage": "provider-reported"
    });
    let saved = app.ok("ai_usage_record", json!({"record": record.to_string()}));
    assert_eq!(saved, "Salvo: AAAAAAAA-0000-0000-0000-000000000001");
    let usage = app.json("ai_usage", json!({}));
    assert_eq!(usage[0]["operation"], "chat");
    assert_eq!(usage[0]["promptCharacters"], 42);
    assert!(
        app.fail("ai_usage_record", json!({"record": "{\"operation\":1}"}))
            .contains("inválido")
    );
}

#[test]
fn reorganize_restore_desfaz_e_refaz_o_recibo_do_apply() {
    let p = Project::new();
    let mut app = p.app();
    let topic = app.json("add_rule_topic", json!({"title":"Solta"}));
    let slug = topic["slug"].as_str().unwrap().to_string();
    let prompt = app.json("reorganize_prompt", json!({}));
    let fingerprint = prompt["fingerprint"].as_str().unwrap().to_string();
    let answer = json!({"actions":[{
        "id":"a1","kind":"move","item":{"concept":"rules","slug": slug},
        "reason":"Agrupar","destination":"grupo","involved":[]}]});
    let proposal = app.ok(
        "reorganize_validate",
        json!({"answer": answer.to_string(), "fingerprint": fingerprint}),
    );
    let acceptance = json!({"selected":["a1"],"conflicts":{}});
    let receipt = app.ok(
        "reorganize_apply",
        json!({"proposal": proposal, "acceptance": acceptance.to_string()}),
    );
    let parsed: Value = serde_json::from_str(&receipt).unwrap();
    for map in ["before", "after"] {
        for bytes in parsed[map].as_object().unwrap().values() {
            assert!(
                bytes.as_str().unwrap().len() % 4 == 0,
                "base64 com padding (Data do Swift)"
            );
        }
    }
    assert!(
        p.path(&format!(".vibedeck/rules/grupo/{slug}.json"))
            .is_file()
    );

    assert_eq!(
        app.ok(
            "reorganize_restore",
            json!({"receipt": receipt, "forward": false})
        ),
        "Desfeito."
    );
    assert!(p.path(&format!(".vibedeck/rules/{slug}.json")).is_file());
    assert!(
        !p.path(&format!(".vibedeck/rules/grupo/{slug}.json"))
            .exists()
    );
    assert_eq!(
        app.ok(
            "reorganize_restore",
            json!({"receipt": receipt, "forward": true})
        ),
        "Refeito."
    );
    assert!(
        p.path(&format!(".vibedeck/rules/grupo/{slug}.json"))
            .is_file()
    );
    assert!(
        app.fail("reorganize_restore", json!({"receipt":"{}","forward":true}))
            .contains("Recibo")
    );
    assert!(
        app.fail("reorganize_restore", json!({"receipt": receipt}))
            .contains("forward")
    );
}

#[test]
fn release_orphaned_solta_ideia_de_topico_apagado_por_fora() {
    let p = Project::new();
    let mut app = p.app();
    let idea = app.json("add_idea", json!({"title":"Promovida"}));
    let slug = idea["slug"].as_str().unwrap().to_string();
    app.ok("add_idea_rule", json!({"idea": slug, "text":"Regra"}));
    let promoted = app.ok("promote_idea", json!({"idea": slug}));
    let topic = promoted
        .lines()
        .next()
        .unwrap()
        .rsplit(": ")
        .next()
        .unwrap()
        .to_string();
    assert_eq!(
        app.json("release_orphaned", json!({})),
        json!({"ideas": [], "patterns": []})
    );
    std::fs::remove_file(p.path(&format!(".vibedeck/rules/{topic}.json"))).unwrap();
    assert_eq!(
        app.json("release_orphaned", json!({}))["ideas"],
        json!([slug])
    );
    assert!(
        app.json("get_idea", json!({"idea": slug}))
            .get("promotedTopic")
            .is_none()
    );
}
