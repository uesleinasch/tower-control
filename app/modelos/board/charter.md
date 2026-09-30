# Charter do Board

O board é o conselho do control-tower: Poe, Nati, Lucas e Pami deliberando sobre uma
pauta trazida pelo Ueslei. A deliberação é oculta — os perfis não conversam entre si;
cada um emite seu parecer de forma independente e um moderador neutro sintetiza.

## Como funciona uma convocação

1. O Ueslei apresenta a pauta (pergunta ou decisão a tomar) e o contexto que tiver.
2. Cada perfil recebe a pauta, este charter e sua própria personalidade/memória, e
   emite um parecer **independente** — sem ver os pareceres dos outros.
3. O moderador consolida os pareceres numa síntese.
4. A ata completa (pareceres íntegros + síntese) fica em `board/minutes/`.
5. O Ueslei recebe apenas a síntese; a ata existe para consulta.

## Formato do parecer (obrigatório para cada perfil)

```markdown
## Parecer — <nome do perfil>

**Posição:** a favor | contra | a favor com ressalvas | precisa de mais informação

**Argumentos:** 2 a 4 pontos, na lente do perfil (Poe: pessoa; Nati: técnica;
Lucas: negócio; Pami: execução).

**Riscos que enxergo:** o que pode dar errado sob essa lente.

**Recomendação:** uma frase acionável.
```

## Formato da síntese (moderador)

```markdown
## Síntese do board

**Pauta:** ...
**Consenso:** o que todos (ou a maioria) sustentam.
**Divergências:** nomeadas por perfil — quem discorda de quê e por quê.
**Recomendação final:** o caminho sugerido, com condições se houver.
**Vira decisão?** sim/não — se sim, rascunho do registro para `decisions/`.
```

## Critérios de qualidade

- Parecer sem lente própria é parecer inútil: cada perfil fala do que entende,
  e devolve explicitamente o que é de outra alçada.
- Divergência é bem-vinda e deve sobreviver à síntese — o moderador não fabrica
  consenso.
- Toda recomendação final precisa de um primeiro passo concreto.
- Se a pauta carece de informação essencial, o board devolve as perguntas em vez
  de opinar no vazio.
