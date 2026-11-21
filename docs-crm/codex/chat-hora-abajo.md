# Hora de mensajes con media abajo

Rama: `feat/chat-composer-lote`
Fecha: 2026-11-20

| Estado | Verificación | Evidencia | Resultado |
|---|---|---|---|
| PASS | Fila inferior normal, alineada a la derecha y con color neutral | `app/javascript/dashboard/components-next/message/bubbles/Base.vue:80-82` | Metadatos usan `mt-1 justify-end text-n-slate-11`; email conserva su padding inferior. |
| PASS | Hora agrupada por minuto y fila de origen/Captain en mensajes intermedios | `app/javascript/dashboard/components-next/message/bubbles/Base.vue:76-77,106-117` | Se mantiene `shouldGroupWithNext`; solo se ocultan hora y estado según la lógica existente. |
| PASS | Mensaje de imagen única y mosaicos | `app/javascript/dashboard/components-next/message/bubbles/Image.vue:8-13`; `app/javascript/dashboard/components-next/message/bubbles/Text/Index.vue:74-76,105-115`; `app/javascript/dashboard/components-next/message/specs/Attachments.spec.js:154-182` | La imagen única deja el overlay; los mosaicos conservan `MediaGrid` y la fila de `BaseBubble`. |
| PASS | Video único y reels | `app/javascript/dashboard/components-next/message/Message.vue:369-379`; `app/javascript/dashboard/components-next/message/bubbles/Video.vue:30-54` | Usan `VideoBubble` con metadatos estándar debajo del video. |
| PASS | Orden, tamaño y colores de origen, Captain, candado, hora y ticks | `app/javascript/dashboard/components-next/message/MessageMeta.vue:140-162`; `app/javascript/dashboard/components-next/message/specs/MessageMeta.spec.js:47-106` | Se conserva el orden DOM, el tamaño de los iconos y los colores de la fila; nota privada conserva candado ámbar. |
| PASS | ESLint focal | `app/javascript/dashboard/components-next/message/MessageMeta.vue:140-162`; `app/javascript/dashboard/components-next/message/specs/Attachments.spec.js:154-182` | `pnpm exec eslint` sobre los cuatro componentes y tres specs tocados pasó sin errores ni warnings. |
| FAIL | Vitest en UTC | `package.json:8`; error en `node_modules/.pnpm/vite@6.4.2.../vite/dist/node/chunks/dep-Dq2t6Dq0.js:35730` | 20 suites no pudieron recolectar tests: Vite no pudo cargar `fake-indexeddb/auto/index.mjs` desde el junction externo `D:\DOCUMENTOS\GITHUB\chatwoot\chatwoot\node_modules`. Cero tests ejecutados. |
| FAIL | Vitest en America/Guayaquil | `package.json:8`; error en `node_modules/.pnpm/vite@6.4.2.../vite/dist/node/chunks/dep-Dq2t6Dq0.js:35730` | Mismo fallo de resolución previo a la recolección; cero tests ejecutados. |

## Qué se quitó

- La prop `overlayMeta` de `Base.vue` y `overlay-meta` de `Image.vue`.
- La clase `media-meta` y sus estilos `absolute bottom-2 end-2`, píldora oscura, blur, padding y overrides blancos.
- La prop `overlay` y sus colores especiales en `MessageMeta.vue` y `MessageStatus.vue`.
- Las specs que medían contraste WCAG sobre la píldora; se sustituyeron por assertions de fila inferior, orden y colores estándar.

No se inició preview ni se tocó Docker. El comportamiento responsive de 390 px y la apariencia clara/oscura no se verificaron en navegador en esta sesión; la fila usa tokens neutrales y sin estilos dependientes de tema.
