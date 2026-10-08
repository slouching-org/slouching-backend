# Original architecture PDF — page 11

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 11 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




  Camada                           Lado            Biblioteca                    Uso

  Criptografia                     Rust            openmls , sframe , ed25519-   MLS, mídia, identidade,
                                                   dalek , spake2 , blake3       pareamento, hashes

  Armazenamento                    Rust            rusqlite (SQLCipher),         Banco local criptografado,
                                                   keyring                       chaves

  Protocolo                        Ambos           prost / protobuf              Mensagens binárias
                                                                                 cliente-servidor

  Gateway                          Elixir          phoenix ou bandit +           WebSocket binário
                                                   websock

  Persistência                     Elixir          ecto , Postgres, oban         Fila de entrega, diretório,
                                                                                 limpeza

  SFU                              Elixir          ex_webrtc                     Chamadas em grupo

  Cluster                          Elixir          libcluster , horde            Distribuição de processos

  Observabilidade                  Elixir          telemetry , OpenTelemetry     Métricas e tracing

  Relay                            Serviço         coturn, iroh-relay            TURN e relay de dados




                                                                                                        Page 11 of 11
```
