# Prueba local del widget de ChatHub

Levanta ChatHub siguiendo [LOCAL_DEV.md](./LOCAL_DEV.md). Esta prueba verifica el widget y la atención humana desde la bandeja.

## Página de prueba

Con el stack local levantado, **nginx en :8080** sirve la página automáticamente:

```powershell
cd D:\DOCUMENTOS\GITHUB\chatwoot\chatwoot
docker compose -f docker-compose.dokploy.yml -f docker-compose.dokploy.fork.yml up -d widget-test
```

Abrir: http://localhost:8080/test-chat.html

Alternativa manual (sin Docker): `python -m http.server 8080` en la carpeta `chatwoot/`.

En Chatwoot → **Settings → Inboxes → Website → Configuration**:

| Campo | Valor |
|-------|--------|
| Website URL | `http://localhost:8080` |
| Allowed domains | `http://localhost:8080` |

En **Installation**, copia `websiteToken` a `test-chat.html` si cambiaste de inbox.

**Error 429 en `/widget`:** Chatwoot limita el widget a 5 cargas/hora por IP. En local pon en `.env`:

```env
ENABLE_RACK_ATTACK_WIDGET_API=false
```

y recrea los contenedores (un `restart` no recarga `.env`):

```bash
docker compose -f docker-compose.dokploy.yml up -d chatwoot-rails chatwoot-sidekiq
```

## Verificación

1. Abre la página de prueba e inicia una conversación como visitante.
2. Comprueba que el mensaje aparece en la bandeja correspondiente.
3. Responde como agente y comprueba que el widget recibe el mensaje.
4. Recarga la página y verifica que se conserva la conversación.

La prueba no necesita un producto externo ni un webhook de bot.
