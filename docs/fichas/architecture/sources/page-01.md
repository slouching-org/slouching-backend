# Original architecture PDF — page 01

**Source:** [architecture-p2p-v0.1.pdf](architecture-p2p-v0.1.pdf), page 1 of 11. Verbatim text extraction; layout may differ from the PDF. Historical design input, not current architecture.

```text
Arquitetura do sistema P2P de comunicação (v0.1)




Arquitetura do sistema P2P de comunicação
(v0.1)
  ​Oct 6, 2026       · ​@Rodrigo Marques Barbosa


Resumo e princípios
O sistema oferece chat (texto, imagem, vídeo, áudio, arquivo), chamadas de voz e vídeo e
espelhamento de tela, em grupo desde a v0.1. O cliente é Rust com Iced; o servidor é Elixir
e nunca vê conteúdo. Tudo se apoia em cinco princípios:

 1. Toda conversa é um grupo MLS, inclusive a de 2 pessoas. Um único modelo de
    criptografia, sem código separado para 1:1 e grupo.
 2. Tudo é evento dentro do grupo. Mensagem, reação, edição, confirmação de leitura,
    convite de chamada e mudança de membros são eventos criptografados.
 3. Mídia criptografada no cliente com SFrame, com chaves derivadas do MLS. P2P
    direto ou SFU vira detalhe de transporte; uma chamada de 2 vira grupo sem renegociar
    criptografia.
 4. O servidor nunca vê conteúdo. Ele ordena, guarda, repassa e esquece.
 5. Tráfego separado pela natureza. Mídia em tempo real tolera perda; dados precisam ser
    confiáveis. Cada um usa a pilha especializada nele.




                                                                                     Page 1 of 11
```
