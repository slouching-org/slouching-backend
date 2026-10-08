# Original architecture PDF — page 10

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 10 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




 1. Fundação: identidade, pareamento SPAKE2, MLS e fila de entrega com ACK. Chat de
     texto ponta a ponta funcionando.
 2. Dados P2P: iroh para chat direto e iroh-blobs para imagens e arquivos, com fallback
     pelo servidor.
 3. Áudio 1:1: cpal, processamento de áudio, Opus, str0m e SFrame.
 4. Vídeo e tela 1:1: codificação por hardware, simulcast e renderização no shader do Iced.
 5. Grupo: SFU no ex_webrtc, migração P2P → SFU, seleção de camadas e de quem fala.
 6. Endurecimento: testes de rede ruim ( tc netem simulando perda, latência e jitter),
     métricas e recuperação de falhas.

Riscos principais:

     Técnico (etapa 3): eco e qualidade de áudio fazem ou quebram um app de VoIP.
     De projeto (etapa 1): se MLS e entrega estiverem certos desde o início, o resto se
     encaixa por cima.
     Desempenho do SFU: ex_webrtc pode exigir troca por str0m em Rust com muitos
     participantes.
     Wayland: captura de tela só via portal, com permissão do usuário a cada sessão.


Bibliotecas de referência
Lista de memória; confira versões e estado de manutenção antes de fixar dependências.


  Camada                           Lado            Biblioteca                  Uso

  Interface                        Rust            iced                        UI e renderização de vídeo
                                                                               via shader

  Runtime                          Rust            tokio                       Atores do core e rede

  Dados P2P                        Rust            iroh , iroh-blobs           QUIC, hole punching, relay,
                                                                               arquivos

  Mídia                            Rust            str0m                       WebRTC sans-IO

  Áudio                            Rust            cpal , audiopus , webrtc-   Captura, Opus, eco e ruído
                                                   audio-processing

  Vídeo                            Rust            ffmpeg-next , openh264      Codificação por hardware
                                                                               e fallback

  Tela                             Rust            xcap , ashpd                Captura; portal no Wayland




                                                                                                    Page 10 of 11
```
