//! Agentes, comandos, skills, kits e importação.
//!
//! - `persona`: criar/editar/encadear (`Agent`, `Command` e `Skill` compartilham o formato);
//! - `flow`: JSON de fluxo (`agent_flow`, `command_flow`, `skill_flow`);
//! - `import` / `files`: leitura local de `.claude/*` e `.codex/*` e `discover` (início guiado);
//! - `kits`: catálogo embutido (`assets/kits/`) e instalação;
//! - `item_discover`: prompt/schema/validação de itens propostos por IA (`ai item-prompt|item-apply`).

pub mod error;
pub mod files;
pub mod flow;
pub mod import;
pub mod item_discover;
pub mod kits;
pub mod persona;

pub use error::{ResourceError, Result};
pub use flow::{AgentFlowNode, AgentFlowStep, flow_for};
pub use import::{
    Discovered, ImportResult, discover, import_agents, import_commands, import_discovered,
    import_skill_files, import_skills,
};
pub use kits::{CatalogKit, InstalledKitItem, KitCatalogItem, KitItemKind, add_kit_items, kits};
pub use persona::{
    Fields, NewPersona, Persona, View, add_next_step, create, group_path, mcp_row,
    remove_next_step, set_provider_or_model, update, with_slug, with_slug_and_group,
};
