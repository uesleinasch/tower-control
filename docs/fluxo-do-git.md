# Fluxo do git

Só vira release o que entra na `Production`. O teste antes do release é o build local, gerado da `development`.

## Branches

- **`Production`**: o que vai para release. Toda tag `v*` aponta para um commit dela, e o `release.yml` recusa a tag que não aponta.
- **`development`**: junta as branches de trabalho. É a branch padrão no GitHub e a única de onde sai build local (`+localN`).
- **`main`**: backup do código. Recebe a `Production` depois de cada release e mais nada.
- **Branches de trabalho** (`feature/<nome>`, `fix/<nome>`, `chore/<nome>`): uma por tarefa, sempre a partir da `Production`. Se a tarefa depende de outra que ainda não foi para release, a branch sai da branch de trabalho da anterior, e as duas são promovidas juntas.

A história não é reescrita: `development`, `Production` e `main` só recebem merge, nunca rebase nem push forçado. Rebase só em branch de trabalho que ainda não foi enviada.

## Dia a dia

1. `git switch -c feature/<nome> Production`.
2. Commits granulares, com o prefixo da área (`ui:`, `servidor:`, `celular:`...).
3. No fim da tarefa: push da branch, PR para a `development` e merge (merge commit). Se a `development` precisar de algo da `Production`, entra por merge.
4. Build local a partir da `development`, instalado no desktop e no celular para testar.

## Release (semanal)

1. `git switch -c release/vX.Y.Z Production`.
2. Cada branch de trabalho escolhida entra na `release/vX.Y.Z` por PR com squash.
3. PR da `release/vX.Y.Z` para a `Production`, com merge.
4. Tag anotada `vX.Y.Z` no commit do merge, e push da tag: o `release.yml` gera o GitHub Release com `.deb` e APK.
5. Apagar a `release/vX.Y.Z` e as branches de trabalho promovidas, local e no remoto.
6. Merge da `Production` na `development`.
7. PR da `Production` para a `main`, com merge.
