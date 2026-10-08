# ADR 0002 — Um dispositivo committer por grupo

**Estado:** aceita pelo dono do produto em 2026-10-07.

## Contexto

MLS requer que membros concordem na sequência de mudanças de chaves e
participantes. Num grupo peer-first, dois Commits concorrentes sobre a mesma
época podem produzir ramificações incompatíveis.

## Decisão

No v0.1, um dispositivo membro designado cria a cadeia de Commits de cada
grupo. Os demais enviam propostas. Nenhum helper/VPS ganha essa autoridade.
Conflitos detectados colocam o grupo em quarentena. Se o dispositivo
designado for perdido permanentemente, o grupo é recriado de forma explícita
com um novo ID e nova verificação.

## Consequências

Mudanças de membros e chaves esperam quando esse dispositivo está offline.
Remoções pendentes exigem pausa de envio protegido. Esta decisão não dispensa
revisão de persistência atômica, autenticação, MLS e detecção de forks.
