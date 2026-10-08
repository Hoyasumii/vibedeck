# Graph Report - vibedeck  (2026-10-08)

## Corpus Check
- 113 files · ~87,130 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 5 file(s) not represented in the graph (top: (none) 1, .resolved 1, .icns 1)

## Summary
- 2354 nodes · 4755 edges · 162 communities (147 shown, 15 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 361 edges (avg confidence: 0.82)
- Token cost: 118,090 input · 5,500 output

## Community Hubs (Navigation)
- CLI Commands
- Claude Stream Parsing
- Project Store Persistence
- Claude Usage Tracking
- Project Model State
- Markdown Editor & Agent View
- Docs, Concepts & CI
- Rule Topics Model
- Idea JSON Schema
- MCP Server
- Claude Session Process
- Ideas & Rule Checks
- Agents & Chat Codable
- Claude Autocomplete
- Model/Effort Pickers
- Claude Chat History
- Review Group UI
- Embedded Terminal
- Claude Chat List
- Doc Viewer
- Core Data Models
- Model Mutations
- Question Cards
- Sidebar Items
- App Root & Recents
- Rules View
- VibeDeck Errors
- Links View
- Chat Transcript
- Shared Framework Imports
- Review Item Model
- Section List View
- App Entry & Commands
- Agent Persistence
- Idea View
- Tab Bar & Styles
- Worker package.json
- Cloud Sync Check
- MCP Install Scope
- Agent Flow Types
- Cloud Session Launch
- Review-Group Schema #1
- Chat Composer
- Rule-Check Schema #1
- Rule-Topic Schema #1
- Rule Check 0521
- Rule Check 0522
- Agent File Parsing
- Review-Group Schema #2
- ProjectWindow (Self)
- ProjectStore Tests
- Rule Check 0225
- Rule Check 0230
- Rule Check 0239
- Rule Check 0242
- Rule Check 0303
- Rule Check 0327
- Rule Check 0333
- Rule Check 0336
- Rule Check 0342
- Rule Check 0413
- Rule Check 0445
- Rule Check 0448
- Rule Check 0456
- Rule Check 0503
- Rule Check 0513 #1
- Rule Check 0513 #2
- Rule Check 0529
- Rule Check 0533
- Rule Check 0537
- Rule Check 0545
- Rule Check 0557
- Rule Check 0559
- Rule Check 0615
- Icon Generator Script
- Review-Group Schema #3
- Review-Group Schema #4
- Rule-Check Schema #2
- Rule-Topic Schema #2
- Sidebar Sections
- File Watcher
- Project Schema #1
- Project Schema #2
- Project Schema #3
- Rule-Check Schema #3
- Idea: adicionar agentes
- Idea: adicionar comandos
- Idea: adicionar configuracoes do app
- Idea: adicionar workflows
- Idea: botao de descubra em onde e regras
- Idea: botao de gerar prompt sobre ideias e revisoes
- Idea: melhorar o md viewer
- Idea: nova interface
- Idea: site do projeto
- tsconfig (tsconfig.json)
- Markdown Frontmatter
- Agent Schema #1
- Project Schema #4
- Cloud Launch Sheet
- Name Prompt Sheet
- Idea Status
- Cloud Session Tests
- Idea: adicionar skills
- Idea: suporte a idiomas
- Rules: build scripts e ci
- Rules: cli e mcp
- Rules: conceitos do produto
- Rules: core e formato de dados
- Rules: dinamicas da interface
- Rules: fluxo padrao
- Rules: interface do app
- Rules: worker e schemas
- Agent Schema #2
- Agent Schema #3
- Project Schema #5
- Project Schema #6
- Review-Group Schema #5
- Rule-Check Schema #4
- Rule-Topic Schema #3
- Rule-Topic Schema #4
- Cloud Sync Status
- Rules: geral
- DMG Background Script
- Agent Schema #4
- Agent Flow Builder
- Cloud Launch Phases
- Review Status
- Project Manifest
- Agent Schema #5
- Session Entry Kinds
- Chat Roles
- Agents Tests
- Review: tela de ia
- Review: tela lateral
- App Icon Branding
- Review-Group Schema #6
- Rule-Check Schema #5
- Rule-Topic Schema #5
- Rule-Topic Schema #6
- Rule-Topic Schema #7
- index (index.ts)
- Agent Schema #6
- Agent Schema #7
- Agent Schema #8
- Agent Schema #9
- Agent Schema #10
- Agent Schema #11
- Review-Group Schema #7
- Rule-Check Schema #6
- Rule-Check Schema #7
- Rule-Check Schema #8
- Rule-Topic Schema #8
- build-app (build-app.sh)
- ClaudeSession (Page)
- ProjectStore (String)
- Package (Package.swift)
- env (env.sh)
- set-schema-url (set-schema-url.sh)
- test (test.sh)

## God Nodes (most connected - your core abstractions)
1. `ProjectStore` - 95 edges
2. `ProjectModel` - 81 edges
3. `ClaudeSession` - 67 edges
4. `ReviewItem` - 36 edges
5. `ReviewGroup` - 36 edges
6. `CodingKeys` - 36 edges
7. `RuleTopic` - 36 edges
8. `VibeDeckError` - 35 edges
9. `ClaudePermissionRequest` - 34 edges
10. `ClaudeChat` - 33 edges

## Surprising Connections (you probably didn't know these)
- `Cloud sessions (claude --cloud)` --semantically_similar_to--> `Cloud session (start_cloud_session / cloud_check)`  [INFERRED] [semantically similar]
  README.md → .vibedeck/AGENTS.md
- `VibeDeck (README)` --semantically_similar_to--> `Conceitos do VibeDeck (concepts doc)`  [INFERRED] [semantically similar]
  README.md → .vibedeck/docs/conceitos-do-vibedeck.md
- `.candidates` --references--> `ClaudeSession`  [INFERRED]
  Sources/VibeDeckApp/ClaudeChatList.swift → Sources/VibeDeckApp/ClaudeSession.swift
- `.preview` --calls--> `Markdown`  [INFERRED]
  Sources/VibeDeckApp/DocView.swift → Sources/VibeDeckCore/ProjectStore.swift
- `.quickAdd` --references--> `ProjectModel`  [INFERRED]
  Sources/VibeDeckApp/ReviewGroupView.swift → Sources/VibeDeckApp/ProjectModel.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Rules enforcement flow (rules_for, check, done gating)** — _vibedeck_agents_rules_for, _vibedeck_agents_submit_rule_check, _vibedeck_agents_rule_check, _vibedeck_agents_review_item, _vibedeck_agents_rule_topic, _vibedeck_docs_conceitos_do_vibedeck_done_blocking [EXTRACTED 1.00]
- **Frontends over VibeDeckCore ProjectStore (app, CLI, MCP)** — readme_vibedeck_app, _vibedeck_agents_vibedeck_cli, _vibedeck_agents_vibedeck_mcp, _vibedeck_docs_conceitos_do_vibedeck_projectstore [INFERRED 0.85]
- **Schema publishing pipeline (worker CI, worker, schema URLs)** — _github_workflows_worker_check_job, _github_workflows_worker_deploy_job, readme_schema_worker, _vibedeck_agents_schema_urls [INFERRED 0.85]
- **VibeDeck Brand Identity** — assets_appicon_v_monogram, assets_appicon_brand_palette, assets_appicon_macos_squircle, assets_appicon_deck_of_cards_metaphor [INFERRED 0.75]

## Communities (162 total, 15 thin omitted)

### Community 0 - "CLI Commands"
Cohesion: 0.06
Nodes (54): Add, AddRule, Agents, Cat, Check, Checks, Cloud, Docs (+46 more)

### Community 1 - "Claude Stream Parsing"
Cohesion: 0.06
Nodes (32): ClaudeEvent, ignored, initialized, permission, permissionModeChanged, result, textDelta, textStarted (+24 more)

### Community 2 - "Project Store Persistence"
Cohesion: 0.08
Nodes (13): ReviewGroup, .openCount, AtomicFile, ProjectStore, .agentDefsDir, .agentsURL, .checksDir, .dataDir (+5 more)

### Community 3 - "Claude Usage Tracking"
Cohesion: 0.05
Nodes (27): ClaudeUsageView, .body, ResetStyle, dayAndTime, time, .sidebarFooter, ClaudeCode, .isInstalled (+19 more)

### Community 4 - "Project Model State"
Cohesion: 0.09
Nodes (8): Entry, .id, GroupEntry, .id, ProjectModel, docs, .body, .body

### Community 5 - "Markdown Editor & Agent View"
Cohesion: 0.06
Nodes (11): AgentView, .agent, .body, .candidates, .flowInspector, Entry, .id, .editor (+3 more)

### Community 6 - "Docs, Concepts & CI"
Cohesion: 0.08
Nodes (37): Swift CI workflow, Swift test job (swift test), Worker check job (sync + typecheck), Worker deploy job (wrangler deploy), Worker CI workflow, agent_flow (chained nextSteps JSON), VibeDeck AGENTS.md guide for AI agents, Cloud session (start_cloud_session / cloud_check) (+29 more)

### Community 7 - "Rule Topics Model"
Cohesion: 0.06
Nodes (33): CodingKeys, author, body, createdAt, description, details, failures, files (+25 more)

### Community 8 - "Idea JSON Schema"
Cohesion: 0.05
Nodes (40): additionalProperties, enum, description, type, format, type, description, $id (+32 more)

### Community 9 - "MCP Server"
Cohesion: 0.12
Nodes (19): ArgumentParser, MCP, AgentRow, CloudStart, DocRow, GroupRow, IdeaRow, ItemRow (+11 more)

### Community 10 - "Claude Session Process"
Cohesion: 0.14
Nodes (5): ClaudeSession, .chosenModel, .current, .effort, Entry

### Community 11 - "Ideas & Rule Checks"
Cohesion: 0.13
Nodes (14): Author, ai, human, Glob, Idea, Rule, RuleCheck, RuleResult (+6 more)

### Community 12 - "Agents & Chat Codable"
Cohesion: 0.06
Nodes (32): Key, slug, CodingKeys, author, createdAt, id, kind, model (+24 more)

### Community 13 - "Claude Autocomplete"
Cohesion: 0.12
Nodes (9): .draft, SuggestionList, .body, ClaudeCompletion, ClaudeSuggestion, .id, ShellCommand, ClaudeCompletionTests (+1 more)

### Community 14 - "Model/Effort Pickers"
Cohesion: 0.07
Nodes (26): .effortPicker, .modelPicker, .modePicker, .label, .label, .help, .label, .symbol (+18 more)

### Community 15 - "Claude Chat History"
Cohesion: 0.13
Nodes (6): ClaudeSession.Entry, .message, ClaudeChat, ClaudeChatMessage, ClaudeChatStore, ClaudeChatsTests

### Community 16 - "Review Group UI"
Cohesion: 0.12
Nodes (12): CommitTextField, .body, FilterChip, .body, KindPalette, .filters, ReviewItemInspector, .body (+4 more)

### Community 17 - "Embedded Terminal"
Cohesion: 0.11
Nodes (7): Delegate, ProjectTerminal, TerminalHost, TerminalPage, .body, .terminal, SwiftTerm

### Community 18 - "Claude Chat List"
Cohesion: 0.09
Nodes (14): ChatRow, .body, .count, ClaudeChatHeader, .body, ClaudeChatList, .body, MentionChips (+6 more)

### Community 19 - "Doc Viewer"
Cohesion: 0.11
Nodes (14): MarkdownUI, ConflictBanner, .body, DocView, .body, .content, .isDirty, .preview (+6 more)

### Community 20 - "Core Data Models"
Cohesion: 0.18
Nodes (9): DocInfo, .id, Link, Project, ReviewItem, ReviewKind, ReviewTarget, .isEmpty (+1 more)

### Community 21 - "Model Mutations"
Cohesion: 0.14
Nodes (9): ReviewGroupView, .body, .group, .header, .items, .list, .quickAdd, .selectedItem (+1 more)

### Community 22 - "Question Cards"
Cohesion: 0.13
Nodes (15): .body, QuestionCard, .answers, .body, Decision, allowAlways, allowOnce, allowSession (+7 more)

### Community 23 - "Sidebar Items"
Cohesion: 0.11
Nodes (18): SidebarItem, agent, claude, doc, group, idea, links, section (+10 more)

### Community 24 - "App Root & Recents"
Cohesion: 0.14
Nodes (11): RecentProjects, RootView, .body, .content, InitProjectSheet, .body, URL, .id (+3 more)

### Community 25 - "Rules View"
Cohesion: 0.16
Nodes (17): View, CheckLabel, .body, ChecksList, .body, ResultRow, .body, .color (+9 more)

### Community 26 - "VibeDeck Errors"
Cohesion: 0.09
Nodes (22): VibeDeckError, agentNotFound, alreadyAProject, ambiguousItem, ambiguousRule, claudeNotInstalled, cloudDirty, cloudNotSynced (+14 more)

### Community 27 - "Links View"
Cohesion: 0.15
Nodes (14): .header, LinkEditor, .body, LinksView, .body, .links, TagChips, .body (+6 more)

### Community 28 - "Chat Transcript"
Cohesion: 0.13
Nodes (12): .chat, .transcript, EntryView, .body, PermissionCard, .body, .detail, PlanCard (+4 more)

### Community 29 - "Shared Framework Imports"
Cohesion: 0.19
Nodes (6): Foundation, Observation, AgentsGuide, SwiftUI, Testing, VibeDeckCore

### Community 30 - "Review Item Model"
Cohesion: 0.10
Nodes (21): CodingKeys, author, createdAt, description, details, id, items, kind (+13 more)

### Community 31 - "Section List View"
Cohesion: 0.18
Nodes (14): SectionRow, SectionListView, .allRows, .allTags, .body, .content, .rows, .suggestedTokens (+6 more)

### Community 32 - "App Entry & Commands"
Cohesion: 0.13
Nodes (9): AppCommands, .body, AppDelegate, FocusedValues, FolderPicker, Notification.Name, VibeDeckApp, .body (+1 more)

### Community 33 - "Agent Persistence"
Cohesion: 0.18
Nodes (3): Agent, Slug, SlugRecord

### Community 34 - "Idea View"
Cohesion: 0.19
Nodes (8): IdeaView, .body, .header, .idea, .promoteButton, .promotedBadge, .statusPicker, .tagsField

### Community 35 - "Tab Bar & Styles"
Cohesion: 0.16
Nodes (6): AppKit, .detail, TabBar, TabButton, .background, .body

### Community 36 - "Worker package.json"
Cohesion: 0.12
Nodes (15): @cloudflare/workers-types, typescript, wrangler, devDependencies, @cloudflare/workers-types, typescript, wrangler, name (+7 more)

### Community 37 - "Cloud Sync Check"
Cohesion: 0.20
Nodes (11): CloudSync, .blocked, .message, Problem, diverged, fetchFailed, localBehind, noOrigin (+3 more)

### Community 38 - "MCP Install Scope"
Cohesion: 0.14
Nodes (13): MCPScope, local, project, user, StatusFilter, all, closed, open (+5 more)

### Community 39 - "Agent Flow Types"
Cohesion: 0.24
Nodes (11): .symbol, AgentFlowNode, AgentFlowStep, NextStep, NextStepKind, agent, command, RuleSeverity (+3 more)

### Community 40 - "Cloud Session Launch"
Cohesion: 0.21
Nodes (5): os, CloudSession, Git, Output, .ok

### Community 41 - "Review-Group Schema #1"
Cohesion: 0.13
Nodes (15): enum, type, properties, description, type, enum, author, details (+7 more)

### Community 42 - "Chat Composer"
Cohesion: 0.20
Nodes (8): ClaudeChatPage, .composer, .emptyState, .isShellMode, .mentions, .pickers, .suggestions, .trigger

### Community 43 - "Rule-Check Schema #1"
Cohesion: 0.15
Nodes (13): enum, format, type, description, type, properties, author, id (+5 more)

### Community 44 - "Rule-Topic Schema #1"
Cohesion: 0.15
Nodes (13): enum, format, type, author, id, severity, text, properties (+5 more)

### Community 45 - "Rule Check 0521"
Cohesion: 0.15
Nodes (12): author, createdAt, failures, files, id, passed, results, reviewItem (+4 more)

### Community 46 - "Rule Check 0522"
Cohesion: 0.15
Nodes (12): author, createdAt, failures, files, id, passed, results, reviewItem (+4 more)

### Community 47 - "Agent File Parsing"
Cohesion: 0.20
Nodes (8): ClaudeAgentFile, Parsed, ClaudeTrigger, Kind, chat, command, file, mention

### Community 48 - "Review-Group Schema #2"
Cohesion: 0.17
Nodes (12): type, type, component, file, route, selector, target, type (+4 more)

### Community 49 - "ProjectWindow (Self)"
Cohesion: 0.29
Nodes (10): NewNamePrompt, agent, doc, group, .id, idea, .placeholder, .title (+2 more)

### Community 51 - "Rule Check 0225"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 52 - "Rule Check 0230"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 53 - "Rule Check 0239"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 54 - "Rule Check 0242"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 55 - "Rule Check 0303"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 56 - "Rule Check 0327"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 57 - "Rule Check 0333"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 58 - "Rule Check 0336"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 59 - "Rule Check 0342"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 60 - "Rule Check 0413"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 61 - "Rule Check 0445"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 62 - "Rule Check 0448"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 63 - "Rule Check 0456"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 64 - "Rule Check 0503"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 65 - "Rule Check 0513 #1"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 66 - "Rule Check 0513 #2"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 67 - "Rule Check 0529"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 68 - "Rule Check 0533"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 69 - "Rule Check 0537"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 70 - "Rule Check 0545"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 71 - "Rule Check 0557"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 72 - "Rule Check 0559"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 73 - "Rule Check 0615"
Cohesion: 0.17
Nodes (11): author, createdAt, failures, files, id, passed, results, $schema (+3 more)

### Community 74 - "Icon Generator Script"
Cohesion: 0.22
Nodes (3): cgPath(), color(), render()

### Community 75 - "Review-Group Schema #3"
Cohesion: 0.18
Nodes (11): type, format, type, properties, description, id, $schema, title (+3 more)

### Community 76 - "Review-Group Schema #4"
Cohesion: 0.18
Nodes (11): items, $ref, type, items, rules, tags, description, items (+3 more)

### Community 77 - "Rule-Check Schema #2"
Cohesion: 0.18
Nodes (11): items, type, type, files, topics, warnings, description, items (+3 more)

### Community 78 - "Rule-Topic Schema #2"
Cohesion: 0.18
Nodes (11): format, type, type, properties, createdAt, description, $schema, title (+3 more)

### Community 79 - "Sidebar Sections"
Cohesion: 0.18
Nodes (8): SidebarSection, agents, .emptyMessage, groups, ideas, .symbol, .title, topics

### Community 81 - "Project Schema #1"
Cohesion: 0.20
Nodes (10): type, minLength, type, properties, description, name, $schema, version (+2 more)

### Community 82 - "Project Schema #2"
Cohesion: 0.20
Nodes (10): format, pattern, type, type, id, label, symbol, properties (+2 more)

### Community 83 - "Project Schema #3"
Cohesion: 0.20
Nodes (10): type, properties, tags, title, url, items, type, type (+2 more)

### Community 84 - "Rule-Check Schema #3"
Cohesion: 0.20
Nodes (10): properties, type, note, ruleId, topic, verdict, format, type (+2 more)

### Community 85 - "Idea: adicionar agentes"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 86 - "Idea: adicionar comandos"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 87 - "Idea: adicionar configuracoes do app"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 88 - "Idea: adicionar workflows"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 89 - "Idea: botao de descubra em onde e regras"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 90 - "Idea: botao de gerar prompt sobre ideias e revisoes"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 91 - "Idea: melhorar o md viewer"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 92 - "Idea: nova interface"
Cohesion: 0.20
Nodes (9): author, createdAt, id, rules, $schema, status, tags, title (+1 more)

### Community 93 - "Idea: site do projeto"
Cohesion: 0.20
Nodes (9): author, body, createdAt, id, rules, $schema, status, title (+1 more)

### Community 94 - "tsconfig (tsconfig.json)"
Cohesion: 0.20
Nodes (9): compilerOptions, lib, module, moduleResolution, noEmit, strict, target, types (+1 more)

### Community 96 - "Agent Schema #1"
Cohesion: 0.22
Nodes (9): enum, properties, author, $schema, title, type, description, minLength (+1 more)

### Community 97 - "Project Schema #4"
Cohesion: 0.22
Nodes (9): $defs, link, reviewKind, additionalProperties, required, type, additionalProperties, required (+1 more)

### Community 98 - "Cloud Launch Sheet"
Cohesion: 0.36
Nodes (3): CloudLaunchSheet, .body, .content

### Community 99 - "Name Prompt Sheet"
Cohesion: 0.25
Nodes (4): NamePromptSheet, .body, SectionSidebarRow, .body

### Community 100 - "Idea Status"
Cohesion: 0.22
Nodes (9): IdeaStatus, approved, discarded, done, exploring, .isClosed, .label, new (+1 more)

### Community 102 - "Idea: adicionar skills"
Cohesion: 0.22
Nodes (8): author, createdAt, id, rules, $schema, status, title, updatedAt

### Community 103 - "Idea: suporte a idiomas"
Cohesion: 0.22
Nodes (8): author, createdAt, id, rules, $schema, status, title, updatedAt

### Community 104 - "Rules: build scripts e ci"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 105 - "Rules: cli e mcp"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 106 - "Rules: conceitos do produto"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 107 - "Rules: core e formato de dados"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 108 - "Rules: dinamicas da interface"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 109 - "Rules: fluxo padrao"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 110 - "Rules: interface do app"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 111 - "Rules: worker e schemas"
Cohesion: 0.22
Nodes (8): createdAt, description, id, paths, rules, $schema, tags, title

### Community 112 - "Agent Schema #2"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 113 - "Agent Schema #3"
Cohesion: 0.25
Nodes (8): properties, enum, type, kind, note, ref, minLength, type

### Community 114 - "Project Schema #5"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 115 - "Project Schema #6"
Cohesion: 0.25
Nodes (8): $ref, items, type, links, reviewKinds, description, items, type

### Community 116 - "Review-Group Schema #5"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 117 - "Rule-Check Schema #4"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 118 - "Rule-Topic Schema #3"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 119 - "Rule-Topic Schema #4"
Cohesion: 0.25
Nodes (8): type, description, items, type, paths, tags, items, type

### Community 120 - "Cloud Sync Status"
Cohesion: 0.25
Nodes (8): CodingKeys, ahead, behind, blocked, branch, dirty, message, remoteURL

### Community 121 - "Rules: geral"
Cohesion: 0.25
Nodes (7): createdAt, description, id, rules, $schema, tags, title

### Community 123 - "Agent Schema #4"
Cohesion: 0.29
Nodes (7): type, tags, tools, items, type, items, type

### Community 125 - "Cloud Launch Phases"
Cohesion: 0.29
Nodes (6): Phase, checked, checking, failed, launched, launching

### Community 127 - "Review Status"
Cohesion: 0.29
Nodes (7): ReviewStatus, done, inProgress, .isClosed, .label, open, wontfix

### Community 128 - "Project Manifest"
Cohesion: 0.29
Nodes (6): id, links, name, reviewKinds, $schema, version

### Community 129 - "Agent Schema #5"
Cohesion: 0.33
Nodes (6): additionalProperties, required, description, items, type, nextSteps

### Community 130 - "Session Entry Kinds"
Cohesion: 0.33
Nodes (6): Kind, assistant, error, notice, tool, user

### Community 131 - "Chat Roles"
Cohesion: 0.33
Nodes (6): Role, assistant, error, notice, tool, user

### Community 133 - "Review: tela de ia"
Cohesion: 0.33
Nodes (5): createdAt, id, items, $schema, title

### Community 134 - "Review: tela lateral"
Cohesion: 0.33
Nodes (5): createdAt, id, items, $schema, title

### Community 135 - "App Icon Branding"
Cohesion: 0.50
Nodes (4): VibeDeck App Icon, Brand Palette (orange, teal on dark charcoal), macOS Rounded-Square Icon Shape, Stylized 'V' Monogram (orange + teal cards)

### Community 136 - "Review-Group Schema #6"
Cohesion: 0.40
Nodes (5): $defs, item, additionalProperties, required, type

### Community 137 - "Rule-Check Schema #5"
Cohesion: 0.40
Nodes (5): additionalProperties, required, results, items, type

### Community 138 - "Rule-Topic Schema #5"
Cohesion: 0.40
Nodes (5): $defs, rule, additionalProperties, required, type

### Community 139 - "Rule-Topic Schema #6"
Cohesion: 0.50
Nodes (4): $ref, rules, items, type

### Community 140 - "Rule-Topic Schema #7"
Cohesion: 0.50
Nodes (4): sourceIdea, description, format, type

### Community 142 - "index (index.ts)"
Cohesion: 0.50
Nodes (3): CORS, Env, fetch()

### Community 143 - "Agent Schema #6"
Cohesion: 0.67
Nodes (3): format, type, createdAt

### Community 144 - "Agent Schema #7"
Cohesion: 0.67
Nodes (3): format, type, id

### Community 145 - "Agent Schema #8"
Cohesion: 0.67
Nodes (3): description, type, model

### Community 146 - "Agent Schema #9"
Cohesion: 0.67
Nodes (3): description, type, prompt

### Community 147 - "Agent Schema #10"
Cohesion: 0.67
Nodes (3): summary, description, type

### Community 148 - "Agent Schema #11"
Cohesion: 0.67
Nodes (3): updatedAt, format, type

### Community 149 - "Review-Group Schema #7"
Cohesion: 0.67
Nodes (3): format, type, createdAt

### Community 150 - "Rule-Check Schema #6"
Cohesion: 0.67
Nodes (3): format, type, createdAt

### Community 151 - "Rule-Check Schema #7"
Cohesion: 0.67
Nodes (3): items, type, failures

### Community 152 - "Rule-Check Schema #8"
Cohesion: 0.67
Nodes (3): reviewItem, format, type

### Community 153 - "Rule-Topic Schema #8"
Cohesion: 0.67
Nodes (3): description, type, details

### Community 155 - "ClaudeSession (Page)"
Cohesion: 0.67
Nodes (3): Page, chat, terminal

### Community 156 - "ProjectStore (String)"
Cohesion: 0.67
Nodes (3): String, .nonEmpty, .trimmed

## Ambiguous Edges - Review These
- `Conceitos do VibeDeck (concepts doc)` → `Sobre o projeto (placeholder notes doc)`  [AMBIGUOUS]
  .vibedeck/docs/sobre-o-projeto.md · relation: conceptually_related_to

## Knowledge Gaps
- **1001 isolated node(s):** `$schema`, `author`, `createdAt`, `failures`, `files` (+996 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1127 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Conceitos do VibeDeck (concepts doc)` and `Sobre o projeto (placeholder notes doc)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `URL` connect `App Root & Recents` to `CLI Commands`, `Project Store Persistence`, `Claude Usage Tracking`, `Project Model State`, `Agents Tests`, `MCP Server`, `Claude Session Process`, `Ideas & Rule Checks`, `Claude Autocomplete`, `Claude Chat History`, `Review Group UI`, `Embedded Terminal`, `Sidebar Items`, `App Entry & Commands`, `Agent Persistence`, `Cloud Session Launch`, `ProjectStore Tests`, `File Watcher`, `Cloud Launch Sheet`, `Cloud Launch Phases`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **Why does `View` connect `Rules View` to `Claude Usage Tracking`, `Markdown Editor & Agent View`, `Claude Autocomplete`, `Review Group UI`, `Embedded Terminal`, `Claude Chat List`, `Doc Viewer`, `Model Mutations`, `Question Cards`, `Sidebar Items`, `App Root & Recents`, `Links View`, `Chat Transcript`, `Section List View`, `Idea View`, `Tab Bar & Styles`, `Chat Composer`, `ProjectWindow (Self)`, `Cloud Launch Sheet`, `Name Prompt Sheet`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `ClaudeSession` connect `Claude Session Process` to `App Entry & Commands`, `Project Model State`, `Model/Effort Pickers`, `Claude Chat History`, `Embedded Terminal`, `Claude Chat List`, `Question Cards`, `Sidebar Items`, `App Root & Recents`, `ClaudeSession (Page)`, `Chat Transcript`, `Shared Framework Imports`?**
  _High betweenness centrality (0.036) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `ProjectModel` (e.g. with `.candidates` and `.copyFlow()`) actually correct?**
  _`ProjectModel` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `$schema`, `author`, `createdAt` to the rest of the system?**
  _1001 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CLI Commands` be split into smaller, more focused modules?**
  _Cohesion score 0.06454388984509467 - nodes in this community are weakly interconnected._