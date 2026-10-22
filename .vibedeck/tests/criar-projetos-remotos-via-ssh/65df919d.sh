#!/usr/bin/env bash
# 65DF919D: IA e scripts de regras aguardam pendências/conflitos; o terminal continua disponível.
# APOSENTADA por D16 (nada a verificar: sem espelho/sincronização/conflito): o projeto SSH não tem mais espelho local: o Core Rust roda no servidor (ssh host vibedeck mcp -C <pasta>) e o app só fala MCP com ele (RemoteWorkspace.swift, CoreStore.sshLocation), sem cache, edição offline, pendências nem conflitos; RemoteWorkspace.requireSynchronized() é um no-op e RemoteExecution.synchronize não faz nada.
# Decisão D16 (estado.md): SSH direto + reconexão com intervalo crescente + offline somente leitura; sem edição offline nem conflito.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
