---
id: 2026-08-22-arquitetura-do-control-tower
date: 2026-08-22
title: Arquitetura do control-tower
status: aceita
tags: [arquitetura, control-tower]
projeto: control-tower
participantes: [ueslei]
---

## Contexto

O control-tower precisa de uma interface de chat dedicada na rede local para conversar
com os perfis e convocar o board. Havia dúvida entre usar MCP, agent com orquestrador
de subagents, ou reutilizar o claude-local-session como interface.

## Decisão

Interface web própria (Bun, porta 7878) com o Claude Agent SDK como motor das
conversas, board com deliberação oculta (pareceres paralelos + síntese) e um MCP
server dedicado apenas a expor as decisões registradas para outras sessões Claude
Code. Monorepo: código e conteúdo juntos neste repositório. Metodologia SDD.

## Alternativas descartadas

- Reutilizar o claude-local-session como interface — o Ueslei quer uma interface
  focada só nesse trabalho.
- API Messages direta — perderia acesso nativo a arquivos e sairia da assinatura.
- Uma sessão Claude Code por perfil — custo e coordenação altos para o board.

## Consequências

- Os perfis leem/escrevem arquivos do repo nativamente (memória e decisões).
- O consumo roda dentro da assinatura do Claude Code existente.
- A primeira decisão registrada é esta — o formato fica validado pelo uso.
