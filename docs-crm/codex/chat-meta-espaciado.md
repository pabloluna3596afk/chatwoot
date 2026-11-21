# Espaciado de hora y estado en burbujas

## Resultado

La fila `MessageMeta` usa una única utilidad: `mt-1 px-3 pb-2`. El contenido de
cada burbuja vive en `data-bubble-content`, con su padding propio. Los valores
en px son la conversión de Tailwind a la escala base de 16 px.

| Tipo | Estado | Antes | Después | Referencias |
|---|---|---|---|---|
| Texto | PASS | Burbuja `px-3 pt-2 pb-1.5`; meta solo `mt-1` (derecha 12 px, abajo 6 px) | Contenido `px-3 pt-2`; meta `mt-1 px-3 pb-2` (derecha 12 px, abajo 8 px) | `bubbles/Text/Index.vue:105`, `bubbles/Base.vue:81` |
| Imagen | PASS | Burbuja `p-1`; meta solo `mt-1` (derecha/abajo 4 px) | Contenido `p-1`; meta `mt-1 px-3 pb-2` (derecha 12 px, abajo 8 px) | `bubbles/Image.vue:11`, `bubbles/Base.vue:81` |
| Mosaico | PASS | Composición de texto; meta sin padding propio | Contenido de texto `px-3 pt-2`; mosaico conserva inset de 4 px; meta `mt-1 px-3 pb-2` | `bubbles/Text/Index.vue:105`, `media/MediaGrid.vue:29` |
| Archivo | PASS | Burbuja `p-2`; meta solo `mt-1` (derecha/abajo 8 px) | Contenido `p-2`; meta `mt-1 px-3 pb-2` | `bubbles/File.vue:9`, `bubbles/Base.vue:81` |
| Vídeo | PASS | Burbuja `p-3`; meta solo `mt-1` (derecha/abajo 12 px) | Contenido `p-1`; meta `mt-1 px-3 pb-2`; radio interior 10 px | `bubbles/Video.vue:30`, `bubbles/Video.vue:36` |
| Audio | PASS | Burbuja `p-2`; meta solo `mt-1` | Contenido `p-2`; meta `mt-1 px-3 pb-2` | `bubbles/Audio.vue:15`, `bubbles/Base.vue:81` |
| Error de carga de imagen | PASS | Burbuja `p-1`; meta solo `mt-1`; marco de fondo siempre presente | Contenido `p-1`; meta común; sin fondo sobre foto y con fondo solo en el placeholder; radio interior 10 px | `media/MediaTile.vue:95`, `specs/Attachments.spec.js:215` |
| Contacto / ubicación | PASS | `BaseAttachment` aplicaba `p-3` a contenido y fila meta | Contenido `p-3`; fila meta común al borde del contenido | `bubbles/BaseAttachment.vue:41`, `bubbles/Base.vue:81` |
| Plantilla WhatsApp | PASS | Burbuja `px-4 py-3`; fila meta sin espaciado compartido | Contenido `px-3 pt-3`; fila meta común `mt-1 px-3 pb-2` | `bubbles/WhatsappTemplate.vue:53` |

## Verificación

| Revisión | Estado | Resultado |
|---|---|---|
| Vitest completo, UTC | PASS | 48 archivos, 448 tests |
| Vitest completo, America/Guayaquil | PASS | 48 archivos, 448 tests |
| Specs de Base y adjuntos, tras el último ajuste, UTC | PASS | 2 archivos, 62 tests |
| Specs de Base y adjuntos, tras el último ajuste, America/Guayaquil | PASS | 2 archivos, 62 tests |
| ESLint de los archivos modificados | PASS | 0 errores; warnings existentes de i18n/formato |
| Preview / Docker | No ejecutado | Solicitado expresamente para esta tarea |

Los comandos de Vitest usaron `vitest.local.config.ts`. No se modificó ni se
incluyó ese archivo en el commit.
