//! Round-trip de todos os JSON gerenciados deste repositório: decodificar tipado e reemitir.
//!
//! Esperado: 464 arquivos, byte a byte, salvo as normalizações documentadas abaixo (cada uma é aplicada ao
//! JSON cru para construir os bytes esperados, e o teste confere que o resultado tipado coincide):
//!
//! * N1 `rule-topic` sem `author`: a regravação grava `"author" : "human"` (S1 de dados.md).
//! * N2 `project`: `codexCloudEnvironment` é removido (D5); `reviewKinds` vazio/ausente vira os 6 padrões;
//!   `id` ausente ganha UUID novo (não ocorre neste repo).
//! * N3 UUID em minúsculas vira MAIÚSCULAS (nenhum caso neste repo).
//! * N4 datas com fração (exceto `RuleCheck.createdAt`) são truncadas a segundos (nenhum caso neste repo).
//! * N5 `tags: []`/`paths: []` e demais vazios "omitidos" saem do arquivo (nenhum caso neste repo).
//!
//! Fora do escopo: os 2 JSON auxiliares escritos à mão em `.vibedeck/tests/` (não são dados do Core).

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use vibedeck_core::json;
use vibedeck_core::model::*;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if e.file_type().unwrap().is_dir() {
            walk(&p, out);
        } else if p.extension().is_some_and(|x| x == "json") {
            out.push(p);
        }
    }
}

#[derive(Default)]
struct Report {
    total: usize,
    identical: usize,
    normalized: Vec<String>,
    failures: Vec<String>,
}

/// Normalizações documentadas aplicadas ao JSON cru (N1, N2); as demais não ocorrem nos dados.
fn normalize(kind: &str, mut v: Value) -> Value {
    if let Value::Object(m) = &mut v {
        match kind {
            "rule-topic" => {
                m.entry("author").or_insert(Value::String("human".into()));
            }
            "project" => {
                m.remove("codexCloudEnvironment");
            }
            _ => {}
        }
    }
    v
}

fn check<T: Serialize + DeserializeOwned>(kind: &str, path: &Path, rep: &mut Report) {
    let raw = fs::read(path).unwrap();
    let rel = path
        .strip_prefix(repo_root())
        .unwrap()
        .display()
        .to_string();
    rep.total += 1;
    let typed: T = match serde_json::from_slice(&raw) {
        Ok(t) => t,
        Err(e) => {
            rep.failures.push(format!("{rel}: não decodifica: {e}"));
            return;
        }
    };
    let out = json::encode(&typed).unwrap();
    if out == raw {
        rep.identical += 1;
        return;
    }
    // Não idêntico: precisa ser exatamente a normalização documentada aplicada ao JSON cru.
    let value: Value = serde_json::from_slice(&raw).unwrap();
    let expected = json::to_vdjson(&normalize(kind, value)).into_bytes();
    if out == expected {
        rep.normalized.push(rel);
    } else {
        rep.failures.push(format!(
            "{rel}: bytes divergem além das normalizações documentadas"
        ));
    }
}

#[test]
fn every_managed_json_roundtrips() {
    let root = repo_root();
    let data = root.join(".vibedeck");
    let mut rep = Report::default();

    check::<Project>("project", &root.join("vibedeck.json"), &mut rep);

    let mut files = Vec::new();
    walk(&data, &mut files);
    files.sort();
    let mut skipped_tests = 0;
    for f in files {
        let rel = f.strip_prefix(&data).unwrap();
        let top = rel
            .components()
            .next()
            .unwrap()
            .as_os_str()
            .to_string_lossy()
            .into_owned();
        match top.as_str() {
            "agents" => check::<Agent>("agent", &f, &mut rep),
            "commands" => check::<Command>("command", &f, &mut rep),
            "skills" => check::<Skill>("skill", &f, &mut rep),
            "workflows" => check::<Workflow>("workflow", &f, &mut rep),
            "ideas" => check::<Idea>("idea", &f, &mut rep),
            "reviews" => check::<ReviewGroup>("review-group", &f, &mut rep),
            "rules" => check::<RuleTopic>("rule-topic", &f, &mut rep),
            "checks" => check::<RuleCheck>("rule-check", &f, &mut rep),
            "runs" => {
                assert_eq!(f.file_name().unwrap(), "run.json", "{f:?}");
                check::<WorkflowRun>("workflow-run", &f, &mut rep)
            }
            "tests" => skipped_tests += 1,
            other => panic!("pasta inesperada com JSON: {other}"),
        }
    }
    eprintln!(
        "round-trip: {} arquivos, {} byte a byte, {} normalizados, {} fora de escopo (tests/)",
        rep.total,
        rep.identical,
        rep.normalized.len(),
        skipped_tests
    );
    for n in &rep.normalized {
        eprintln!("  normalizado: {n}");
    }
    assert!(
        rep.failures.is_empty(),
        "falhas:\n{}",
        rep.failures.join("\n")
    );
    assert_eq!(skipped_tests, 2, "os 2 JSON de tests/ citados em dados.md");
    assert_eq!(rep.total, 464);
}
