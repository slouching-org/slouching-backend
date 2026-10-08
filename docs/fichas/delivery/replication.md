# Entrega e réplicas

**Estado:** especificada; não implementada.

Cada app manterá outbox e inbox locais persistentes, IDs estáveis de evento,
deduplicação e recibos distintos para salvo localmente, guardado por outro
peer, recebido por dispositivo, lido, expirado ou falhou. Amigos podem aceitar
cópias de **ciphertext** com quota e prazo explícitos. Um helper opcional
oferece a mesma função por mais tempo.

Uma cópia em helper não prova entrega ao destinatário. Nenhum membro ganha
histórico anterior automaticamente ao ingressar no grupo. A conversa
persistente e o chat temporário da chamada têm retenções diferentes.

Ver [spec detalhada](../architecture/backend.md#5-delivery-and-replication).
