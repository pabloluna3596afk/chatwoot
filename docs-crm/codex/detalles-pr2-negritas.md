# Detalles PR2 — nombres en negrita

## Verificación

| Resultado | Comprobación | Evidencia |
|---|---|---|
| PASS | Coincidencia literal, sensible a mayúsculas, primera aparición, con límite de palabra Unicode y nombres de varias palabras | [activityMessageHighlighter.js](../../app/javascript/dashboard/helper/activityMessageHighlighter.js:7), [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js:150) |
| PASS | Escapa metacaracteres de regex; solo inserta `<b>` en nodos de texto del DOM saneado | [activityMessageHighlighter.js](../../app/javascript/dashboard/helper/activityMessageHighlighter.js:5), [activityMessageHighlighter.js](../../app/javascript/dashboard/helper/activityMessageHighlighter.js:17), [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js:176) |
| PASS | El contenido hostil se sanea; atributos no participan en la búsqueda ni conservan `onerror` | [activityMessageHighlighter.js](../../app/javascript/dashboard/helper/activityMessageHighlighter.js:66), [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js:188) |
| PASS | Sin `activity.names` o sin coincidencia no se añade negrita | [activityMessageHighlighter.js](../../app/javascript/dashboard/helper/activityMessageHighlighter.js:61), [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js:200) |
| PASS | Se conserva la eliminación del punto final y el tiempo relativo; se conserva la pastilla compacta | [Activity.vue](../../app/javascript/dashboard/components-next/message/bubbles/Activity.vue:15), [Activity.vue](../../app/javascript/dashboard/components-next/message/bubbles/Activity.vue:37), [Activity.vue](../../app/javascript/dashboard/components-next/message/bubbles/Activity.vue:47), [Activity.spec.js](../../app/javascript/dashboard/components-next/message/bubbles/specs/Activity.spec.js:43) |
| PASS | El seeder usa `ActivityMessageNames` para Captain, asignación humana, equipo, etiqueta y automatización | [captain_decisions_demo.rb](../../lib/seeders/captain_decisions_demo.rb:122), [captain_decisions_demo.rb](../../lib/seeders/captain_decisions_demo.rb:145), [dev_captain_decisions_demo_spec.rb](../../spec/lib/tasks/dev_captain_decisions_demo_spec.rb:16) |
| PASS | Vitest en UTC: 28 pruebas aprobadas | `Activity.spec.js` con `vitest.local.config.ts`, `TZ=UTC` |
| PASS | Vitest en America/Guayaquil: 28 pruebas aprobadas | `Activity.spec.js` con `vitest.local.config.ts`, `TZ=America/Guayaquil` |
| PASS | ESLint en el componente, helper y spec | `pnpm exec eslint` sobre los tres archivos JavaScript/Vue modificados |
| PASS | Spec del seeder: 3 ejemplos, 0 fallos | `rspec-local.sh ... spec/lib/tasks/dev_captain_decisions_demo_spec.rb` |
| PASS | Preview reconstruido y reiniciado; conectado como `agent@detalles.example.invalid` con `storageState` aislado. El DOM mostró diez `<b class="nm font-semibold text-n-slate-12">` para Captain, Maria, Alex Rivera, Soporte, priority y automatización | Playwright en `http://localhost:3042/app/accounts/1/conversations/1`; no se modificaron ni limpiaron tokens/sesiones en BD |
| FAIL | No se pudo confirmar visualmente el cierre de sesión del superadmin ya abierto en Chrome | Se accionó “Cerrar sesión”; Computer Use detuvo la lectura posterior porque no pudo determinar la URL actual. No se alteraron sesiones ni tokens en BD. |

## Build

`pnpm exec vite build` terminó correctamente (5884 módulos). Vite reportó únicamente los avisos habituales de tamaño de chunks y datos de Browserslist desactualizados.
