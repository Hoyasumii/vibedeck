#!/usr/bin/env bash
# E6158DCD: sem conexão, as edições continuam no cache local e ficam pendentes.
# NÃO SE APLICA ao Core Rust / app atual: o projeto SSH não tem mais espelho local: o Core Rust roda no servidor (ssh host vibedeck mcp -C <pasta>) e o app só fala MCP com ele (RemoteWorkspace.swift, CoreStore.sshLocation), sem cache, edição offline, pendências nem conflitos; sem conexão o app não edita dados (toda leitura e escrita passa pelo Core no servidor).
# Decisão de arquitetura (briefing-regras.md, F01 arquitetura.md): sem espelho local nem sincronização.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
