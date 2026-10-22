#!/usr/bin/env bash
# 80A692FB: o conflito mostra versão local e remota e permite escolher qual preservar.
# NÃO SE APLICA ao Core Rust / app atual: o projeto SSH não tem mais espelho local: o Core Rust roda no servidor (ssh host vibedeck mcp -C <pasta>) e o app só fala MCP com ele (RemoteWorkspace.swift, CoreStore.sshLocation), sem cache, edição offline, pendências nem conflitos.
# Decisão de arquitetura (briefing-regras.md, F01 arquitetura.md): sem espelho local nem sincronização.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
