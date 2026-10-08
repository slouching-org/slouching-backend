# Encadeamento de commits MLS

**Estado:** regra de política parcialmente codificada; MLS ainda ausente.

O criador de cada grupo registra um **dispositivo membro designado** como
único autor de Commits aceitos no v0.1. Outros membros enviam propostas. Cada
Commit aponta para a época/hash anterior. Uma duplicata idêntica é inofensiva;
dois hashes distintos para o mesmo sucessor indicam equivocação e colocam o
grupo em quarentena. Sem o dispositivo designado, mudanças de membros param.
Se ele se perde definitivamente, membros verificados criam explicitamente um
grupo novo. Não há eleição ou troca silenciosa.

`peer/src/lib.rs` implementa somente a checagem de autor, predecessor,
duplicata e conflito **após** autenticação externa. Não armazena estado em disco,
não verifica assinatura/MLS, não gera Welcome e não realiza o fluxo de
propostas. Dados de rede não podem ser passados diretamente a esse módulo.

Ver [ADR 0002](adr-0002-designated-committer.md) e
[spec detalhada](../architecture/backend.md#6-mls-commit-rule-one-designated-member-device-v01-decision).
