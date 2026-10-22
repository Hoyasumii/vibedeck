#!/usr/bin/env bash
# A83A6E65: reconexão automática com intervalo crescente, botão Reconectar; senha só com interação do usuário.
# NÃO SE APLICA ao Core Rust / app atual: não existe mais laço de reconexão automática com intervalo crescente (V2RemoteEnvironment só tem o botão Reconectar, que pede senha apenas por ação do usuário); o laço pertencia à sincronização do espelho local, removido com o Core Rust no servidor.
# Decisão de arquitetura (briefing-regras.md, F01 arquitetura.md): sem espelho local nem sincronização.
# Sai com 77 (n/a) em vez de passar; o motivo também está em `details` da regra.
exit 77
