# Rotas entre pares

**Estado:** especificadas; não implementadas.

Na mesma rede local, peers poderão se descobrir ou trocar endereço e se
autenticar diretamente. Na internet, rota direta depende de endereçamento,
NAT e firewall. Um membro pode manter um endpoint público ou um relay/SFU em
PC ou VPS. Nenhum serviço de terceiro deve ser habilitado silenciosamente.

TURN/relay transporta bytes; SFU encaminha mídia de grupo. A interface
distingue rota direta, relay, SFU e indisponível, com medições reais. Sem rota
permitida, mostra erro em vez de conexão fictícia.

Ver [spec detalhada](../architecture/backend.md#4-connection-modes).
