//! Normalizações e defaults do decoder/encoder (dados.md §2 e §3), com fixtures sintéticas.

use serde_json::{Value, json};
use vibedeck_core::json;
use vibedeck_core::model::*;

fn reemit<T: serde::Serialize + serde::de::DeserializeOwned>(v: Value) -> Value {
    let t: T = serde_json::from_value(v).unwrap();
    serde_json::to_value(&t).unwrap()
}

#[test]
fn project_drops_cloud_field_and_defaults_kinds() {
    let out = reemit::<Project>(json!({
        "name": "p", "codexCloudEnvironment": "env", "reviewKinds": [],
        "id": "82283a6d-4139-4386-a516-606a89be658c"
    }));
    assert!(out.get("codexCloudEnvironment").is_none());
    assert_eq!(out["id"], "82283A6D-4139-4386-A516-606A89BE658C");
    assert_eq!(out["version"], 1);
    assert_eq!(out["links"], json!([]));
    assert_eq!(out["reviewKinds"].as_array().unwrap().len(), 6);
    assert_eq!(
        out["reviewKinds"][0],
        json!({"id":"disable","label":"Inativar","symbol":"nosign"})
    );
    assert!(
        out.get("stack").is_none() && out.get("patterns").is_none() && out.get("claude").is_none()
    );
    // id ausente: UUID novo e válido
    let a: Project = serde_json::from_value(json!({"name": "p"})).unwrap();
    let b: Project = serde_json::from_value(json!({"name": "p"})).unwrap();
    assert_ne!(a.id, b.id);
    assert!(serde_json::from_value::<Project>(json!({})).is_err()); // name é obrigatório
}

#[test]
fn project_children_defaults() {
    let out = reemit::<Project>(json!({
        "name": "p",
        "links": [{"url": "https://x.y/z"}],
        "claude": [{"url": "https://claude.ai/artifact/Abc%20d"}],
        "stack": [{"icon": "rust", "note": "", "tags": []}],
        "patterns": [{"id": "tdd", "summary": "", "note": ""}]
    }));
    assert_eq!(out["links"][0]["title"], "https://x.y/z");
    assert_eq!(out["claude"][0]["title"], "Abc d");
    assert_eq!(out["claude"][0]["kind"], "artifact");
    assert_eq!(
        out["stack"][0],
        json!({"icon":"rust","name":"rust","author":"human"})
    );
    assert_eq!(
        out["patterns"][0],
        json!({"id":"tdd","name":"tdd","author":"human"})
    );
}

#[test]
fn dates_are_truncated_and_uuid_uppercased() {
    let out = reemit::<ReviewGroup>(json!({
        "title": "t",
        "id": "0a708007-1a32-4187-afdf-44f51e9b1920",
        "createdAt": "2026-10-09T03:17:31.999Z",
        "tags": [],
        "items": [{"title": "i", "createdAt": "2026-10-09T00:17:31-03:00"}]
    }));
    assert_eq!(out["createdAt"], "2026-10-09T03:17:31Z");
    assert_eq!(out["id"], "0A708007-1A32-4187-AFDF-44F51E9B1920");
    assert!(out.get("tags").is_none());
    let item = &out["items"][0];
    assert_eq!(item["updatedAt"], "2026-10-09T03:17:31Z");
    assert_eq!(item["kind"], "note");
    assert_eq!(item["status"], "open");
    assert_eq!(item["priority"], "normal");
    assert_eq!(item["author"], "human");
    assert!(item.get("rules").is_none() && item.get("target").is_none());
}

#[test]
fn null_counts_as_absent() {
    let out = reemit::<ReviewGroup>(
        json!({"title": "t", "items": null, "tags": null, "description": null}),
    );
    assert_eq!(out["items"], json!([]));
    assert!(out.get("description").is_none());
}

#[test]
fn unknown_keys_are_dropped() {
    let out = reemit::<Idea>(json!({"title": "t", "bogus": 1}));
    assert!(out.get("bogus").is_none());
}

#[test]
fn rule_topic_author_and_rule_test() {
    let out = reemit::<RuleTopic>(json!({
        "title": "t",
        "rules": [
            {"text": "a", "test": {"command": "x.sh"}},
            {"text": "b", "test": {"reason": "subjetiva"}},
            {"text": "c", "test": {"mode": "script", "command": "y", "ruleHash": "abc", "generatedAt": "2026-01-01T00:00:00Z"}}
        ]
    }));
    assert_eq!(out["author"], "human");
    assert_eq!(out["rules"][0]["severity"], "must");
    assert_eq!(out["rules"][0]["test"]["mode"], "script");
    assert_eq!(out["rules"][0]["test"]["ruleHash"], "");
    assert_eq!(out["rules"][1]["test"]["mode"], "manual");
    assert!(out["rules"][1]["test"].get("command").is_none());
    assert_eq!(out["rules"][2]["test"]["ruleHash"], "abc");
}

#[test]
fn idea_readiness_dependencies_and_defaults() {
    let d1 = "AAAAAAAA-0000-0000-0000-000000000001";
    let out = reemit::<Idea>(json!({
        "title": "t", "readiness": {"viable": "talvez"},
        "dependencies": [d1, d1.to_lowercase(), "BBBBBBBB-0000-0000-0000-000000000002"]
    }));
    assert!(out.get("readiness").is_none(), "malformado é descartado");
    assert_eq!(
        out["dependencies"],
        json!([d1, "BBBBBBBB-0000-0000-0000-000000000002"])
    );
    assert_eq!(out["status"], "new");
    assert_eq!(out["rules"], json!([]));
    let ok = reemit::<Idea>(json!({"title": "t", "readiness": {"viable": true, "missing": []}}));
    assert_eq!(ok["readiness"]["viable"], true);
    assert_eq!(ok["readiness"]["fingerprint"], "");
    assert!(ok["readiness"].get("missing").is_none());
    assert!(ok["readiness"].get("checkedAt").is_some());
}

#[test]
fn agents_commands_skills() {
    let a = reemit::<Agent>(
        json!({"title": "A", "createdAt": "2026-01-01T00:00:00Z", "providerSettings": {"codex": {"effort": "high"}}}),
    );
    assert_eq!(a["prompt"], "");
    assert_eq!(a["updatedAt"], "2026-01-01T00:00:00Z");
    assert_eq!(a["providerSettings"], json!({"codex": {"effort": "high"}}));
    let c = reemit::<Command>(json!({"title": "C", "argumentHint": "<x>"}));
    assert_eq!(c["argumentHint"], "<x>");
    let s = reemit::<Skill>(
        json!({"title": "S", "sourcePath": "/abs/SKILL.md", "nextSteps": [{"ref": "r"}]}),
    );
    assert_eq!(s["sourcePath"], "/abs/SKILL.md");
    assert_eq!(s["nextSteps"][0], json!({"kind": "agent", "ref": "r"}));
}

#[test]
fn workflow_steps() {
    let w = reemit::<Workflow>(json!({
        "title": "W",
        "steps": [
            {"ref": "rev", "id": "  ", "maxVisits": 0, "transitions": [{"verdict": "  OK ", "to": "x"}, {"when": "", "to": "y"}]},
            {"ref": "dev", "id": " dev-2 ", "maxVisits": 3, "kind": "skill"}
        ]
    }));
    assert_eq!(w["steps"][0]["id"], "rev");
    assert!(w["steps"][0].get("maxVisits").is_none());
    assert_eq!(
        w["steps"][0]["transitions"][0],
        json!({"verdict": "OK", "to": "x"})
    );
    assert_eq!(w["steps"][0]["transitions"][1], json!({"to": "y"}));
    assert_eq!(w["steps"][1]["id"], "dev-2");
    assert_eq!(w["steps"][1]["maxVisits"], 3);
    assert_eq!(w["steps"][1]["kind"], "skill");
}

#[test]
fn rule_check_milliseconds_and_defaults() {
    let c: RuleCheck = serde_json::from_value(json!({
        "id": "e876c608-0000-0000-0000-000000000000",
        "createdAt": "2026-10-09T03:17:31.836Z",
        "results": [{"topic": "t", "ruleId": "e876c608-0000-0000-0000-000000000001", "verdict": "pass", "source": "agent"}]
    }))
    .unwrap();
    assert_eq!(c.author, Author::Ai);
    assert_eq!(c.file_name(), "20261009-031731-e876c608.json");
    let v = serde_json::to_value(&c).unwrap();
    assert_eq!(v["createdAt"], "2026-10-09T03:17:31.836Z");
    assert!(
        v["results"][0].get("source").is_none(),
        "source=agent é omitido"
    );
    assert_eq!(v["passed"], false);
    assert_eq!(v["failures"], json!([]));
    assert!(v.get("pending").is_none());
    let s = reemit::<RuleCheck>(
        json!({"createdAt": "2026-10-09T03:17:31Z", "results": [{"topic":"t","ruleId":"E876C608-0000-0000-0000-000000000001","verdict":"fail","source":"script","exitCode":1}]}),
    );
    assert_eq!(s["createdAt"], "2026-10-09T03:17:31.000Z");
    assert_eq!(s["results"][0]["source"], "script");
    assert_eq!(s["results"][0]["exitCode"], 1);
}

#[test]
fn workflow_run_defaults() {
    let r = reemit::<WorkflowRun>(json!({
        "workflow": "w",
        "history": [{"step": "a", "verdict": "  ", "summary": " ok ", "at": "2026-01-01T00:00:00Z"}],
        "questions": [{"number": 1, "step": "a", "question": "?", "createdAt": "2026-01-01T00:00:00Z"}]
    }));
    assert_eq!(r["provider"], "claude");
    assert_eq!(r["status"], "running");
    assert_eq!(r["cycle"], 1);
    assert_eq!(
        r["history"][0],
        json!({"step": "a", "summary": "ok", "cycle": 1, "at": "2026-01-01T00:00:00Z"})
    );
    assert_eq!(r["questions"][0]["options"], json!([]));
    assert_eq!(r["questions"][0]["multiple"], false);
    assert!(r.get("current").is_none() && r.get("checkpoint").is_none());
}

#[test]
fn empty_target_object_is_kept_verbatim() {
    let out = reemit::<ReviewGroup>(json!({"title": "t", "items": [{"title": "i", "target": {}}]}));
    let bytes = json::to_vdjson(&out);
    assert!(bytes.contains("\"target\" : {\n\n      }"), "{bytes}");
}

#[test]
fn invalid_values_are_errors() {
    assert!(serde_json::from_value::<Idea>(json!({"title": "t", "status": "nope"})).is_err());
    assert!(serde_json::from_value::<Idea>(json!({"title": "t", "id": "xyz"})).is_err());
    assert!(serde_json::from_value::<Idea>(json!({"title": "t", "createdAt": "ontem"})).is_err());
    assert!(
        serde_json::from_value::<Idea>(
            json!({"title": "t", "id": "82283a6d413943868a516606a89be658c"})
        )
        .is_err()
    );
}
