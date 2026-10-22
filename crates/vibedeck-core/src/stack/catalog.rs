//! Catálogo embutido de padrões (32 templates, `assets/patterns/catalog.json`) e categorias.

use std::collections::BTreeMap;
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use super::{Result, StackError, trim_non_empty};
use crate::model::RuleSeverity;
use crate::slug;

const CATALOG_JSON: &str = include_str!("../../assets/patterns/catalog.json");

/// Regra que um padrão do catálogo traz para o seu tópico.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PatternRuleTemplate {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    #[serde(default)]
    pub severity: RuleSeverity,
}

/// Padrão do catálogo embutido, com regras prontas.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PatternTemplate {
    pub id: String,
    pub name: String,
    pub category: String,
    pub summary: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    pub rules: Vec<PatternRuleTemplate>,
}

impl PatternTemplate {
    /// Casa id, nome ou alias ignorando caixa, acentos e pontuação ("Ports & Adapters" = "ports-adapters").
    pub fn matches_exactly(&self, reference: &str) -> bool {
        let key = slug::make(reference);
        !key.is_empty()
            && std::iter::once(&self.id)
                .chain(std::iter::once(&self.name))
                .chain(self.aliases.iter())
                .any(|s| slug::make(s) == key)
    }

    pub fn matches_containing(&self, reference: &str) -> bool {
        let key = slug::make(reference);
        !key.is_empty()
            && [&self.id, &self.name, &self.summary]
                .into_iter()
                .chain(self.aliases.iter())
                .any(|s| slug::make(s).contains(&key))
    }
}

pub struct PatternCatalog;

impl PatternCatalog {
    /// Os 32 templates, na ordem do catálogo.
    pub fn all() -> &'static [PatternTemplate] {
        static ALL: OnceLock<Vec<PatternTemplate>> = OnceLock::new();
        ALL.get_or_init(|| {
            serde_json::from_str(CATALOG_JSON).expect("catálogo de padrões embutido é válido")
        })
    }

    pub fn find(reference: &str) -> Option<&'static PatternTemplate> {
        Self::all().iter().find(|t| t.matches_exactly(reference))
    }

    /// Sem consulta (ou só espaços) devolve tudo.
    pub fn search(query: Option<&str>) -> Vec<&'static PatternTemplate> {
        match query.and_then(trim_non_empty) {
            None => Self::all().iter().collect(),
            Some(q) => Self::all()
                .iter()
                .filter(|t| t.matches_containing(&q))
                .collect(),
        }
    }

    /// Resolve todas as referências ou falha (sem resolver nada) com sugestões para as desconhecidas.
    pub fn resolve(refs: &[String]) -> Result<Vec<&'static PatternTemplate>> {
        let mut found: Vec<&'static PatternTemplate> = Vec::new();
        let mut unknown: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for reference in refs {
            match Self::find(reference) {
                Some(t) => {
                    if !found.iter().any(|f| f.id == t.id) {
                        found.push(t);
                    }
                }
                None => {
                    let suggestions = Self::search(Some(reference))
                        .into_iter()
                        .take(5)
                        .map(|t| t.id.clone())
                        .collect();
                    unknown.insert(reference.clone(), suggestions);
                }
            }
        }
        if unknown.is_empty() {
            Ok(found)
        } else {
            Err(StackError::UnknownPatterns(unknown))
        }
    }
}

pub struct PatternCategory;

impl PatternCategory {
    pub const ALL: [&'static str; 5] = ["practices", "architecture", "domain", "design", "custom"];

    /// Rótulo em PT; categoria desconhecida vira `capitalized`; ausente, "Outros".
    pub fn label(id: Option<&str>) -> String {
        match id {
            Some("practices") => "Práticas".into(),
            Some("architecture") => "Arquitetura".into(),
            Some("domain") => "Domínio".into(),
            Some("design") => "Design".into(),
            Some("custom") => "Personalizados".into(),
            Some(other) => capitalized(other),
            None => "Outros".into(),
        }
    }
}

/// `String.capitalized`: primeira letra de cada palavra em maiúscula, o resto em minúscula.
fn capitalized(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut start = true;
    for c in s.chars() {
        if c.is_alphanumeric() {
            if start {
                out.extend(c.to_uppercase());
            } else {
                out.extend(c.to_lowercase());
            }
            start = false;
        } else {
            out.push(c);
            start = true;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const NEW_CATEGORIES: [(&str, &str); 8] = [
        ("bdd", "practices"),
        ("design-by-contract", "practices"),
        ("modular-monolith", "architecture"),
        ("event-driven", "architecture"),
        ("value-object", "domain"),
        ("domain-service", "domain"),
        ("composite", "design"),
        ("proxy", "design"),
    ];

    #[test]
    fn catalogo_expandido_tem_os_templates_esperados() {
        let existing = [
            "tdd",
            "solid",
            "dependency-injection",
            "functional-core",
            "clean-code",
            "hexagonal",
            "clean-architecture",
            "layered",
            "mvvm",
            "mvc",
            "ddd",
            "cqrs",
            "event-sourcing",
            "repository",
            "strategy",
            "observer",
            "factory",
            "builder",
            "adapter",
            "decorator",
            "facade",
            "command",
            "state",
            "singleton",
        ];
        assert_eq!(PatternCatalog::all().len(), 32);
        let ids: std::collections::BTreeSet<_> = PatternCatalog::all()
            .iter()
            .map(|t| t.id.as_str())
            .collect();
        let want: std::collections::BTreeSet<_> = existing
            .iter()
            .copied()
            .chain(NEW_CATEGORIES.iter().map(|(id, _)| *id))
            .collect();
        assert_eq!(ids, want);
        for t in PatternCatalog::all() {
            assert_eq!(slug::make(&t.id), t.id);
            assert!(!t.name.trim().is_empty());
            assert!(!t.summary.trim().is_empty());
            assert!(PatternCategory::ALL.contains(&t.category.as_str()));
            assert!(!t.rules.is_empty());
        }
        for (id, category) in NEW_CATEGORIES {
            assert_eq!(PatternCatalog::find(id).unwrap().category, category);
        }
    }

    #[test]
    fn toda_referencia_resolve_sem_ambiguidade() {
        for t in PatternCatalog::all() {
            let refs = std::iter::once(&t.id)
                .chain(std::iter::once(&t.name))
                .chain(t.aliases.iter());
            for r in refs {
                let matches: Vec<_> = PatternCatalog::all()
                    .iter()
                    .filter(|x| x.matches_exactly(r))
                    .map(|x| x.id.as_str())
                    .collect();
                assert_eq!(matches, [t.id.as_str()], "ref {r}");
                assert_eq!(PatternCatalog::find(r).unwrap().id, t.id);
            }
        }
    }

    #[test]
    fn regras_novas_trazem_verificacao_concreta() {
        for (id, _) in NEW_CATEGORIES {
            for rule in &PatternCatalog::find(id).unwrap().rules {
                let d = rule.details.as_deref().unwrap();
                assert!(d.starts_with("Verificar:"));
                assert!(!d["Verificar:".len()..].trim().is_empty());
            }
        }
    }

    #[test]
    fn busca_e_aliases() {
        assert_eq!(
            PatternCatalog::find("Ports & Adapters").unwrap().id,
            "hexagonal"
        );
        assert_eq!(
            PatternCatalog::find("domain-driven design").unwrap().id,
            "ddd"
        );
        assert_eq!(PatternCatalog::search(None).len(), 32);
        assert_eq!(PatternCatalog::search(Some("  ")).len(), 32);
        assert!(
            PatternCatalog::search(Some("hexagon"))
                .iter()
                .any(|t| t.id == "hexagonal")
        );
        let err = PatternCatalog::resolve(&["tdd".into(), "hexagon".into()]).unwrap_err();
        match err {
            StackError::UnknownPatterns(m) => {
                assert!(m["hexagon"].contains(&"hexagonal".to_string()))
            }
            e => panic!("{e}"),
        }
        let ok = PatternCatalog::resolve(&["TDD".into(), "tdd".into(), "cqrs".into()]).unwrap();
        assert_eq!(
            ok.iter().map(|t| t.id.as_str()).collect::<Vec<_>>(),
            ["tdd", "cqrs"]
        );
    }

    #[test]
    fn rotulos() {
        assert_eq!(PatternCategory::label(Some("practices")), "Práticas");
        assert_eq!(PatternCategory::label(None), "Outros");
        assert_eq!(PatternCategory::label(Some("meu tipo")), "Meu Tipo");
    }

    #[test]
    fn severidade_should_preservada() {
        let solid = PatternCatalog::find("solid").unwrap();
        assert_eq!(solid.rules[2].severity, RuleSeverity::Should);
        assert_eq!(solid.rules[0].severity, RuleSeverity::Must);
        assert_eq!(PatternCatalog::find("mvvm").unwrap().rules[2].details, None);
    }
}
