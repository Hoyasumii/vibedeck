//! Cliente HTTP do Skill Icons contra um servidor local (sem rede pública).

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

use serde_json::{Value, json};
use vibedeck_core::stack::{SkillIconTheme, SkillIcons, SkillIconsApi};

/// Servidor de uma resposta por conexão; `handler` recebe o corpo JSON-RPC e devolve (status, content-type, corpo).
struct Mock {
    url: String,
    stop: Arc<AtomicBool>,
    requests: Arc<std::sync::Mutex<Vec<Value>>>,
}

impl Mock {
    fn start(handler: impl Fn(&Value) -> (u16, String, String) + Send + 'static) -> Mock {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/mcp", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
        let (stop2, requests2) = (stop.clone(), requests.clone());
        thread::spawn(move || {
            for stream in listener.incoming() {
                if stop2.load(Ordering::SeqCst) {
                    break;
                }
                let Ok(mut stream) = stream else { continue };
                let Some(body) = read_request(&mut stream) else {
                    continue;
                };
                requests2.lock().unwrap().push(body.clone());
                let (status, ctype, text) = handler(&body);
                let _ = write!(
                    stream,
                    "HTTP/1.1 {status} X\r\ncontent-type: {ctype}\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}",
                    text.len()
                );
            }
        });
        Mock {
            url,
            stop,
            requests,
        }
    }
}

impl Drop for Mock {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = TcpStream::connect(
            self.url
                .trim_start_matches("http://")
                .trim_end_matches("/mcp"),
        );
    }
}

fn read_request(stream: &mut TcpStream) -> Option<Value> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 1024];
    let header_end = loop {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(p) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break p + 4;
        }
    };
    let head = String::from_utf8_lossy(&buf[..header_end]).to_lowercase();
    let len: usize = head
        .lines()
        .find_map(|l| l.strip_prefix("content-length:"))
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0);
    while buf.len() < header_end + len {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
    }
    serde_json::from_slice(&buf[header_end..header_end + len]).ok()
}

fn rpc_text(payload: &Value) -> String {
    json!({"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":payload.to_string()}]}})
        .to_string()
}

fn catalog() -> Value {
    json!({"total": 2, "icons": [
        {"id":"swift","name":"Swift","category":"language","themed":false,"aliases":[]},
        {"id":"kubernetes","name":"Kubernetes","category":"devops","themed":false,"aliases":["k8s"]}
    ]})
}

#[test]
fn search_envia_os_argumentos_e_decodifica() {
    let mock = Mock::start(|_| (200, "application/json".into(), rpc_text(&catalog())));
    let api = SkillIcons::new(&mock.url);
    let icons = api.search(Some("sw"), Some("language"), Some(10)).unwrap();
    assert_eq!(icons.len(), 2);
    assert_eq!(icons[1].aliases, ["k8s"]);
    let sent = mock.requests.lock().unwrap()[0].clone();
    assert_eq!(sent["method"], "tools/call");
    assert_eq!(sent["params"]["name"], "skill_icons_search");
    assert_eq!(
        sent["params"]["arguments"],
        json!({"query":"sw","category":"language","limit":10})
    );
    // consulta vazia não é enviada; catalog() pede o limite máximo
    api.catalog().unwrap();
    let sent = mock.requests.lock().unwrap()[1].clone();
    assert_eq!(sent["params"]["arguments"], json!({"limit": 631}));
}

#[test]
fn badge_e_resposta_sse() {
    let mock = Mock::start(|_| {
        let body = rpc_text(&json!({"url":"https://i/x","icons":["swift"]}));
        (
            200,
            "text/event-stream".into(),
            format!("event: message\ndata: {body}\n\n"),
        )
    });
    let api = SkillIcons::new(&mock.url);
    let badge = api
        .badge(&["swift".to_string()], Some(SkillIconTheme::Dark), None)
        .unwrap();
    assert_eq!(badge.markdown, "![Stack](https://i/x)");
    assert_eq!(badge.icons, ["swift"]);
    let sent = mock.requests.lock().unwrap()[0].clone();
    assert_eq!(sent["params"]["name"], "skill_icons_badge");
    assert_eq!(
        sent["params"]["arguments"],
        json!({"icons":["swift"],"theme":"dark"})
    );
}

#[test]
fn erros_http_e_do_servidor_viram_indisponivel() {
    let mock = Mock::start(|_| (503, "text/plain".into(), "fora".into()));
    let err = SkillIcons::new(&mock.url).catalog().unwrap_err();
    assert_eq!(
        err.to_string(),
        "Skill Icons indisponível: HTTP 503 em skill_icons_search."
    );

    let mock = Mock::start(|_| {
        (
            200,
            "application/json".into(),
            json!({"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"quebrou"}}).to_string(),
        )
    });
    let err = SkillIcons::new(&mock.url).catalog().unwrap_err();
    assert_eq!(err.to_string(), "Skill Icons indisponível: quebrou");

    // porta fechada: erro de conexão, não pânico
    let closed = {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        format!("http://{}/mcp", l.local_addr().unwrap())
    };
    let err = SkillIcons::new(closed).catalog().unwrap_err();
    assert!(
        err.to_string().starts_with("Skill Icons indisponível: "),
        "{err}"
    );
}
