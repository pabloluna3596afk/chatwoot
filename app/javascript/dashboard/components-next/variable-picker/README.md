# VariablePicker

Use this thin ComboBox wrapper whenever a feature chooses one CRM variable. P1 consumers are Flow ?Guardar en? and template ?Crear copia con variables? mappings. Other pickers remain unchanged until their planned migration.

```vue
<VariablePicker mode="read" v-model="metaAlias" />
<VariablePicker
  mode="write"
  :model-value="block.save_to?.target || ''"
  :attributes="attributes"
  :scopes="['system', 'contact']"
  :filter="binding => writableFor(binding, block)"
  allow-none
  @update:model-value="setSaveTo"
/>
```

- `read` emits the existing Meta alias (`name`), displaying the human label and alias. `write` emits `canonicalPath` and displays only the human label. Never use the alias as a write target.
- `scopes` restricts the ordered system/contact/conversation/appointment groups. `filter(binding)` adds the caller?s eligibility rules; Flow uses catalog `writableFor(binding, block)`, including numeric inputs, options and formulas.
- `allowNone` adds an empty value, with optional `allowNoneLabel`. `disabled` and `hasError` forward to ComboBox. Other attributes (ARIA label, test ID) forward to ComboBox.
- Account definitions load through `useTemplateBindings`. A caller that already owns definitions can pass reactive `attributes`; it remains responsible for updating them after the modal refreshes the store.
- An administrator gets the shared ?Create new attribute? footer and existing AddAttribute modal. Closing it refreshes definitions. Formula attributes remain readable and cannot be selected for writing.
- The teleported menu targets a local portal in the consumer?s scroll area. It participates in layout, is capped at 20rem, and scrolls its options before the consumer?s fixed footer.

## Catalog and future consumers

`buildBindings` extends the existing entries without changing names, keys, order, defaults or resolution. Metadata: `scope`, `canonicalPath`, Meta alias `name`, `type`, `options`, `readable`, `writable`, `formula`, `requiresContext`. `system` groups standard fields, even when their required context is contact or conversation. Custom attribute scopes describe their owner.

`APPOINTMENT_BINDINGS` describes the existing template aliases separately so ordinary message defaults do not gain appointment expressions. `cita` and `tema` describe appointment.title, `fecha` appointment.date, `hora` appointment.time, and `asistente` assistant.name. P1 emits their aliases exactly as before; it adds no Captain resolution or sending behavior.

Captain and future consumers should supply their available scopes/context and eligibility filter, then adapt the selected alias/path to their existing request contract. Server Drops remain the source of values; `resolveLiquid` is only a partial browser preview and does not resolve appointment or assistant expressions. Missing-value policies, common writers and other picker migrations belong to later phases. Do not copy groups, labels or the modal into consumers. All picker copy lives under `VARIABLE_PICKER` in en/es variables.json.
