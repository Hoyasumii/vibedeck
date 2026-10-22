#!/usr/bin/env bash
# ED782F45: o acesso aos arquivos remotos usa só ssh e utilitários POSIX; nenhum executável VibeDeck no servidor.
# NÃO SE APLICA ao Core Rust / app atual: o projeto remoto agora exige o executável vibedeck no servidor: o Core Rust roda lá (ssh host vibedeck mcp -C <pasta>), localizado por RemoteExecution.launcher; só o fallback de instalação (SFTP/sem vibedeck) foi removido.
# Decisão de arquitetura (briefing-regras.md, F01 arquitetura.md): sem espelho local nem sincronização.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
