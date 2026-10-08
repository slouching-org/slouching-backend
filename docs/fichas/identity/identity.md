# Identidade local

**Estado:** especificada; não implementada.

O dispositivo criará sua própria identidade de assinatura e folha MLS. Não há
conta ou email obrigatório. Nome e familiar são escolhas de perfil, diferentes
da identidade criptográfica. A comparação de fingerprint/QR com outro membro
é o ato que permite rotulá-lo como verificado.

Hoje a tela de onboarding no repositório de frontend salva somente nome e
familiar em `localStorage`
para **prévia visual**. Ela declara que não gerou chave. Nenhum outro módulo
deve tratar esse perfil como identidade autenticada.

Pendências de segurança: formato e proteção da chave local, múltiplos
dispositivos, recuperação, política de troca de chave e derivação exata da
comparação visual. Ver [modelo de confiança](../architecture/backend.md#3-trust-and-security-model).
