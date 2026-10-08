# Original architecture PDF — page 05

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 5 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




fluxo completo · mensagens e chamadas

Uma mensagem sem ACK volta ao outbox e é reenviada com o mesmo ID; quando alguém
entra ou sai de uma chamada, o MLS gera nova época e a rota é reavaliada.


Identidade e pareamento
Cada dispositivo tem sua própria chave; o usuário é o conjunto dos seus dispositivos,
assinado por uma chave de identidade.

     Chaves de dispositivo: Ed25519, guardadas no chaveiro do sistema operacional (crate
     keyring ).
     Adicionar contato: código curto ou QR code com SPAKE2 (crate spake2 ), no estilo
     Magic Wormhole. O servidor só serve de ponto de encontro; as chaves públicas
     trocadas são autenticadas sem confiar nele.
     Vincular novo dispositivo: QR code exibido no dispositivo já logado, com o mesmo
     mecanismo.
     Número de segurança: impressão digital das chaves visível para verificação manual
     entre contatos.


Criptografia
MLS protege mensagens e chaves de grupo; SFrame protege a mídia com chaves
derivadas do MLS.

     MLS (RFC 9420) com openmls . Entrada e saída de membros custam O(log n), com
     forward secrecy e post-compromise security nativos.
     SFrame (RFC 9605) para áudio e vídeo, com a chave tirada do exporter secret do MLS.
     Quando alguém sai, o MLS avança de época, a chave do SFrame troca junto e quem saiu
     deixa de entender a chamada.
     Arquivos: chave aleatória por arquivo e endereçamento por hash BLAKE3. Chave e
     hash viajam dentro da mensagem MLS.
     Armazenamento local: SQLite com SQLCipher ( rusqlite com bundled-sqlcipher ),
     chave do banco no chaveiro do sistema.

Limite conhecido: o cabeçalho RTP de nível de áudio (RFC 6464) fica visível ao SFU para
detectar quem fala. O SFU sabe quem fala e quando, nunca o que é dito — a mesma
escolha de Signal e Google Meet.




                                                                                    Page 5 of 11
```
