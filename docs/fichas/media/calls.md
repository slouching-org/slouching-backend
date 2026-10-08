# Chamadas e captura

**Estado:** especificadas; não implementadas.

Uma chamada tem grupo MLS separado contendo somente seus participantes.
Áudio/vídeo usam chaves derivadas desse grupo; membros da conversa que não
entraram não recebem chaves de mídia. Dois peers tentam rota direta. Mesh
atende grupos pequenos dentro de limites medidos; SFU operado por membro é
opcional. Captura de microfone, câmera, tela e áudio de sistema respeita
permissões do SO.

Hoje a tela de chamada no repositório de frontend usa cenas JPEG e controles
**demonstrativos**. Não abre
dispositivos nem conecta peers. Exibe essa limitação no cabeçalho, no rodapé
e nos estados de ação.

Ver [spec detalhada](../architecture/backend.md#7-calls-files-and-temporary-room-chat).
