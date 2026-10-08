# Original architecture PDF — page 07

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 7 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




  Participantes                                Rota                  Motivo

  2                                            P2P direto, TURN de   Latência mínima
                                               fallback

  3 ou mais                                    SFU                   Upload constante: 1 stream enviado,
                                                                     não N-1

  Espelhamento para                            SFU                   Um emissor para muitos
  vários


A troca de rota é transparente: quando a terceira pessoa entra, os clientes conectam ao
SFU, migram os tracks e fecham o P2P. Como o SFrame já está ativo, nada é renegociado na
criptografia.

No SFU, cada receptor recebe a camada de simulcast que sua banda suporta. O áudio
repassado é o dos 3 mais altos; o vídeo em alta só de quem fala ou está fixado, os demais
em miniatura.


Chat efêmero da chamada
Cada sala de chamada tem um chat que vive só na memória dos participantes
conectados: quem está na sala guarda e serve o histórico, e quando o último sai, o chat
deixa de existir. O servidor nunca guarda nada dele.

Ciclo de vida:

 1. Primeiro a entrar: cria o log do chat em RAM, sem gravar no SQLCipher.
 2. Mensagens: difundidas entre os presentes via iroh-gossip , cifradas na época MLS
      da chamada. Anexos vão por iroh-blobs , servidos por quem já tem o arquivo.
 3. Alguém entra: pede o histórico a um peer presente (o de menor latência) por um
      stream iroh direto. Quanto mais gente na sala, mais fontes servindo o chat.
 4. Alguém sai: os demais continuam servindo; nada se perde enquanto houver pelo
    menos um conectado.
 5. Último sai: a memória é liberada e o chat some.

Decisões de projeto:

      Histórico para quem chega: por causa da forward secrecy do MLS, quem entra não
      consegue decifrar mensagens de épocas anteriores. A solução é o peer que serve o
      histórico reenviá-lo cifrado na época nova, direto para quem chegou.




                                                                                                    Page 7 of 11
```
