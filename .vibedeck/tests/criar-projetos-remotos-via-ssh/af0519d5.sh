#!/usr/bin/env bash
# AF0519D5: projeto SSH recente reabre offline com dados e pendências do cache e indica Desconectado.
# NÃO SE APLICA ao Core Rust / app atual: o projeto SSH não tem mais espelho local: o Core Rust roda no servidor (ssh host vibedeck mcp -C <pasta>) e o app só fala MCP com ele (RemoteWorkspace.swift, CoreStore.sshLocation), sem cache, edição offline, pendências nem conflitos; os recentes guardam só a URL ssh://, e reabrir exige reconectar (V2RemoteEnvironment mostra conectando/conectado/offline).
# Decisão de arquitetura (briefing-regras.md, F01 arquitetura.md): sem espelho local nem sincronização.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
