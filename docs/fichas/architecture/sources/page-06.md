# Original architecture PDF — page 06

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 6 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




Tráfego de dados: iroh
O iroh entrega em uma pilha só QUIC, hole punching, port mapping (UPnP/PCP), IPv6 e
relay de fallback.

     Chat P2P quando o destinatário está online — a rota mais rápida.
     Arquivos via iroh-blobs : transferência verificada em streaming (BLAKE3), vinda de
     várias fontes ao mesmo tempo. Num grupo, quem já baixou ajuda a distribuir; o servidor
     é só mais uma fonte.
     Destinatário offline: a mensagem segue pelo servidor (ver Servidor Elixir).


Tráfego de mídia: WebRTC
Mídia usa WebRTC via str0m no cliente; o processamento de áudio é o componente que
mais define a qualidade percebida.

     Transporte: str0m , WebRTC sans-IO, sem runtime escondido. Você controla threads e
     latência; estimativa de banda embutida.
     Processamento de áudio (essencial): webrtc-audio-processing , bindings do
     libwebrtc para cancelamento de eco, supressão de ruído e controle de ganho.
     Áudio: cpal para captura e reprodução; Opus em quadros de 20 ms com FEC e DTX.
     Câmera: H.264 por hardware (VideoToolbox, NVENC, VAAPI, Media Foundation) via
     ffmpeg-next ; fallback openh264 . Simulcast em 3 camadas.
     Tela: AV1 ou VP9 com ferramentas de conteúdo de tela quando houver hardware;
     senão H.264. Resolução alta, 5 a 15 fps.
     Captura de tela: xcap no Windows, macOS e X11. No Wayland, obrigatoriamente
     PipeWire + xdg-desktop-portal (crate ashpd ).



Topologia das chamadas
Duas pessoas falam direto; a partir de três, a mídia passa pelo SFU.




                                                                                    Page 6 of 11
```
