# Original architecture PDF — page 09

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 9 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




Cliente Rust
O cliente é um workspace Cargo em que a interface só exibe estado e envia intenções.


  Crate              Responsabilidade

   proto             Tipos gerados do protobuf

   crypto            openmls, SFrame, identidade

   net               iroh e cliente WebSocket

   media             Captura, codecs e str0m, em threads dedicadas de
                     tempo real (nunca no tokio)

   core              Atores que orquestram tudo; não sabe que a
                     interface existe

   app               Iced; conversa com o core via Subscription


Vídeo no Iced: widget shader (wgpu), com os planos YUV/NV12 do decoder enviados
direto como texturas e conversão para RGB na GPU. Sem conversão na CPU, 9 ou mais
vídeos rodam sem esforço.

Com o core independente da interface, ele pode ser compilado depois para mobile
(interface nativa via uniffi ) ou para web.



Metas de qualidade

  Métrica                                          Meta        Como atingir

  Áudio boca a ouvido                              < 150 ms    Opus 20 ms, jitter buffer adaptativo

  Início de chamada 1:1                            <1s         Candidatos ICE pré-coletados com o app aberto

  Mensagem P2P                                     < 100 ms    Conexão iroh já aberta

  Mensagem pelo servidor                           < 300 ms    WebSocket persistente

  Troca de rede (Wi-Fi ↔ 4G)                       Sem perda   Migração de conexão QUIC; ICE restart na mídia




Roteiro até a v0.1 e riscos
A v0.1 fecha com chamadas e espelhamento em grupo; cada etapa se apoia na anterior.




                                                                                                        Page 9 of 11
```
