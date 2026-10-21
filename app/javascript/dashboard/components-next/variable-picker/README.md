# VariablePicker

`VariablePicker` wraps the shared ComboBox. Its authority is Rails `GET /variables`;
`useVariableCatalog` shares metadata and in-flight requests by account and surface.
No record values are cached. See `docs/VARIABLES_ENGINE.md` for the API contract.

```vue
<VariablePicker
  v-model="descriptorId"
  surface="message"
  @select="insert($event.expression)"
/>
<VariablePicker
  mode="write"
  value-format="path"
  :model-value="block.save_to?.target || ''"
  :scopes="['system', 'contact']"
  :filter="binding => writableFor(binding, block)"
  allow-none
  @update:model-value="setSaveTo"
/>
```

- The default value is the descriptor `id`; custom attributes retain `reference.definitionId`.
  `select` emits the descriptor with its exact server expression. Never infer Liquid from its key.
- `value-format="alias"` adapts Meta names; `value-format="path"` adapts existing Flow save targets.
  These adapters preserve persisted contracts. Read and write both use the server catalog.
- `surface` controls available contexts. `scopes` and `filter` narrow eligibility for a caller.
  Write additionally requires `writable`, no `managedBy`, and the requested `writeContext`
  (default `whatsapp_flow`). Calendar derivatives and formulas remain read only.
- Loading, retry, empty results and unknown mappings are shared. Errors never emit a value change.
  Existing unknown mappings remain visible with a diagnostic.
- Administrators get the existing AddAttribute modal. Closing it refreshes attributes and the
  shared catalog. The ComboBox menu is teleported, searchable, keyboard navigable and bounded
  by the consuming drawer when one supplies `comboboxBoundary`.

Current consumers: template creation/copy/mapping, manual template Parser (send center,
new conversation and reply), automation template action, Captain template configuration,
and WhatsApp Flow save targets. Captain samples and legacy write targets retain adapters.
The capture writer and Captain runtime are separate work.

Text consumers also use this catalog: canned Add/Edit, WootWriter cursor VariableList,
the shared InsertVariableButton, macros through MacroNode, automation text and attribute
actions, and the live campaign editor. `presentation="insert"` keeps a braces button;
`presentation="caret"` reuses CaretAnchoredPicker with the existing trigger and keyboard.
Read insertions use the server expression verbatim. Attribute targets require write
capability in automation and keep the legacy raw attribute key at the persistence boundary.
Campaign sending and existing Liquid resolution remain outside this selector migration.

Manual preview uses Rails statuses: `missing` asks for a value; `unavailable` diagnoses the
missing context and blocks sending until corrected. Automation and Captain runtime policies
are unchanged by this selector migration.
