# Revisión de pastillas de actividad Captain

20 de noviembre de 2026. Preview local con datos ficticios en [http://localhost:3042/app/accounts/1/conversations/1](http://localhost:3042/app/accounts/1/conversations/1), usuario `admin@detalles.example.invalid`.

| Criterio | Estado | Evidencia |
|---|---|---|
| Pastilla compacta, centrada y limitada a 90% | PASS | [Activity.vue:25-49](../../app/javascript/dashboard/components-next/message/bubbles/Activity.vue) usa `w-fit max-w-[90%]`, centrado flex, padding `px-3 py-1`, y mantiene el texto/tiempo en una fila. El trigger Captain ocupa 24 × 24 px; no hay saltos `<br>`. |
| Centro de cada pastilla alineado con el hilo (±2 px) | PASS | Preview real a 1440 × 1000: hilo centro x=990,5 px. Actividad de evaluación x=990,50 (Δ 0,00 px); cierre por falta de respuesta x=990,49 (Δ −0,01 px); confirmación x=990,49 (Δ −0,01 px). |
| Ancho cercano al contenido y no al hilo | PASS | Anchos medidos: 501,59 px (55,8% del hilo de 899 px), 521,95 px (58,1%) y 291,08 px (32,4%). El contenido de texto mide 386,38 / 406,73 / 175,86 px; el ancho restante corresponde al botón de 24 px, tiempo de ~49 px, padding horizontal de 24 px y separaciones. |
| Envoltura natural con icono alineado a la primera línea | PASS | Preview real a 520 px: la actividad larga envuelve a dos líneas dentro de una pastilla de 453,59 px; centro del hilo y pastilla x=260 px (Δ 0,00 px). El top del botón queda 1 px antes de la primera línea de texto. Sin saltos forzados. |
| Icono al inicio de nota de traspaso y acceso accesible | PASS | [CaptainHandoff.vue:29-48](../../app/javascript/dashboard/components-next/message/bubbles/CaptainHandoff.vue) coloca el control antes de la nota; [Base.vue:18,107-119](../../app/javascript/dashboard/components-next/message/bubbles/Base.vue) evita el trigger duplicado en metadatos. El preview confirma botón 24 × 24 px, `aria-label` y `aria-expanded="false"`; specs verifican apertura, cierre y el mismo panel ([CaptainGenerationDetails.spec.js:232-269](../../app/javascript/dashboard/components-next/message/specs/CaptainGenerationDetails.spec.js)). |
| Specs de actividad y traspaso | PASS | [Activity.spec.js:43-145](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js) cubre orden, fuente, pastilla compacta y texto largo; [CaptainHandoff.spec.js:88-100](../../app/javascript/dashboard/components-next/message/bubbles/specs/CaptainHandoff.spec.js) verifica el icono al inicio. |
| Vitest en UTC y America/Guayaquil | PASS | 32/32 specs en cada zona horaria, con `vitest.local.config.ts`. |
| ESLint focalizado en componentes y specs | PASS | 0 errores. Queda una advertencia ya existente de clave i18n dinámica en `CaptainHandoff.vue:42`. |
| Bundle de producción | PASS | `pnpm exec vite build`: 5883 módulos transformados; build completado. Vite conservó sus avisos habituales de chunks grandes e importación mixta. |

## Capturas del preview

- [Escritorio, 1440 × 1000](capturas-detalles-pr2/pastillas-compactas.png)
- [Viewport estrecho, 520 × 900, texto envuelto](capturas-detalles-pr2/pastillas-compactas-520.png)

## Evidencia de código

- [Activity.vue:25-49](../../app/javascript/dashboard/components-next/message/bubbles/Activity.vue): ancho intrínseco con tope, alineación y envoltura interior.
- [CaptainGenerationDetails.vue:63-68](../../app/javascript/dashboard/components-next/message/CaptainGenerationDetails.vue): trigger de 24 px, etiqueta accesible y estado expandido.
- [CaptainHandoff.vue:45-48](../../app/javascript/dashboard/components-next/message/bubbles/CaptainHandoff.vue): trigger antes del texto de traspaso.
- Specs: [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js), [CaptainHandoff.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/CaptainHandoff.spec.js), [CaptainGenerationDetails.spec.js](../../app/javascript/dashboard/components-next/message/specs/CaptainGenerationDetails.spec.js).
