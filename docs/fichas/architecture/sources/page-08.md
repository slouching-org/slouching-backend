# Original architecture PDF — page 08

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 8 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




     Integridade: cada mensagem é assinada pelo autor (Ed25519) e encadeada por hash
     BLAKE3. Quem recebe o histórico de um peer consegue verificar que nada foi alterado
     ou omitido.
     Ordem: relógio lógico híbrido (HLC) mais o ID UUIDv7 como desempate, para todos
     verem a mesma ordem sem servidor.
     Sem ACK nem outbox: ao contrário das mensagens normais, este chat não tem
     entrega garantida a quem está offline. Isso é intencional.
     Limite de memória: cada cliente guarda no máximo um teto configurável (padrão
     sugerido: 5.000 mensagens ou 200 MB de anexos); acima disso, descarta os itens mais
     antigos.
     Rede ruim: se a conexão direta falhar, o tráfego passa pelo iroh-relay, que só vê bytes
     cifrados.

Risco aceito: se todos caírem ao mesmo tempo (queda de rede geral), o chat se perde,
mesmo que a intenção fosse continuar a conversa.


Servidor Elixir
Cada conversa e cada chamada é um processo BEAM, supervisionado e distribuído pelo
cluster.

     Gateway: um WebSocket binário por dispositivo, mensagens em protobuf ( prost no
     Rust, protobuf no Elixir, mesmo .proto ). Phoenix, ou Bandit + WebSock puro, mais
     enxuto para protocolo binário.
     Delivery Service do MLS: um GenServer por grupo ordena os commits, garantindo que
     todos concordem com a ordem das épocas sem locks.
     Fila de entrega: pelo menos uma vez, com IDs UUIDv7 e deduplicação no cliente — na
     prática, exatamente uma vez. A mensagem fica no Postgres até o ACK de cada
     dispositivo e então é apagada. Oban cuida de expiração e limpeza.
     Blobs offline: arquivos criptografados em MinIO ou S3 até todos confirmarem o
     recebimento.
     Diretório: chaves públicas e KeyPackages do MLS, para adicionar alguém offline a um
     grupo.
     SFU: ex_webrtc , um processo por participante; se um trava, só ele cai.
     TURN: coturn, mais relay do iroh hospedado por você.
     Infraestrutura: libcluster , Horde (registro distribuído de processos), telemetry e
     OpenTelemetry desde o primeiro dia.

Trade-off a monitorar: se o SFU em ex_webrtc virar gargalo de CPU, a saída é um SFU em
Rust com str0m , controlado pelo Elixir. A interface entre os dois é pequena.



                                                                                       Page 8 of 11
```
