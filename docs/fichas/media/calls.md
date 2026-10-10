# Chamadas e captura

> **Architecture note:** the source PDF assigns desktop capture, Opus, and
> SFrame to Rust, and the optional group SFU to Elixir. [ADR 0005](../architecture/adr-0005-elixir-server-core.md)
> preserves that language boundary.

**Estado atual entre os repositórios:** o cliente Rust/Iced já implementa uma
chamada direta entre dois dispositivos. O grupo MLS dedicado protege a mídia;
oferta e resposta WebRTC são sinalizadas pelo QUIC pinado, e a chamada recebida
aguarda aceite explícito. O cliente captura e reproduz Opus via CPAL e protege
os quadros com SFrame. Também há chat temporário em DataChannel, vídeo H.264
protegido para câmera, tela ou janela, e controles de parada.

Os testes locais validam negociação host ICE/DTLS, áudio em loopback,
fragmentação e decodificação de vídeo protegido e encerramento do
compartilhamento. Ainda falta validar captura e reprodução entre máquinas,
permissões reais e caminhos VPN. O cliente mantém uma única sessão WebRTC ativa
por dispositivo; chamadas de três ou mais participantes ainda não estão
implementadas.

**Responsabilidade Elixir:** `ex_webrtc` 0.17.0 está travado no backend. Há
componentes internos para responder ofertas WebRTC, negociar uma track de
áudio por membro remoto, encaminhar RTP opaco e repassar mensagens binárias
limitadas pelo DataChannel confiável `slouching-call-v1`. Eles removem o peer
quando a conexão termina e não decifram SFrame. Ainda faltam coordenador de
sala, admissão derivada e verificável pelo estado MLS, sinalização autenticada,
rota de chamada, modo SFU no cliente e transição de topologia. Esses
componentes não habilitam chamadas em grupo nem entre redes diferentes. O
relay de texto/Iroh não é um relay de mídia WebRTC.

Também não estão implementados cancelamento de eco, supressão de ruído,
controle automático de ganho, TURN nem limites de capacidade medidos para mesh
ou SFU. A chamada de duas pessoas tem testes locais; ainda não há uma promessa
de capacidade para chamadas em grupo. O cliente e seu estado atual estão
descritos na [ficha de chamadas do frontend](https://github.com/slouching-org/slouching-frontend/blob/main/docs/fichas/media/calls.md).

Ver a [especificação detalhada](../architecture/backend.md#7-calls-files-and-temporary-room-chat)
e o [plano de tecnologia](../architecture/tech-stack.md).
