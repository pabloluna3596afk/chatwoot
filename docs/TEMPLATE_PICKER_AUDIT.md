# Template drawer picker audit

The new, edit and copy views now render ChatHub's existing `components-next/combobox/ComboBox.vue`.
`TemplateComboBox.vue` only supplies a local teleport target and the existing attribute CTA. It does not
replace the trigger, search field, option rows or group headers. No shared components or Flow files were changed.

| Selector | Component | Matches Flow? |
| --- | --- | --- |
| Idioma / Language (new, edit, copy) | `TemplateComboBox` → ChatHub `ComboBox` | Yes: shared trigger/list, teleport, explicit placeholder and search; disabled during edit. |
| Bandeja / Inbox (multiple inboxes or validation error) | `TemplateComboBox` → ChatHub `ComboBox` | Yes: shared trigger/list, teleport and channel placeholder; automatic search above six choices, like Flow's short pickers. |
| Header type / Sin encabezado (new/copy; existing header in edit) | `TemplateComboBox` → ChatHub `ComboBox` | Yes: shared trigger/list, teleport and header placeholder; short list uses automatic search. Edit keeps the existing format locked. |
| Copy variable mappings | `TemplateComboBox` → ChatHub `ComboBox` | Yes: explicit search and placeholder, ordered groups, admin-only attribute CTA, and the same existing attribute modal as Flow. |
| Añadir variable / Add variable (new) | `TemplateComboBox` → ChatHub `ComboBox` | Yes: replaces `DropdownMenu`; named variables use search/groups/admin CTA; positional mode offers the next number without search. |

There are no native `<select>` elements or `DropdownMenu` instances left in the drawer. Category radio cards,
named/positional mode buttons and add-button actions are explicit choices/actions, not dropdowns.

## Placement and appearance

Flow's save-target picker teleports a floating list into the page. The drawer uses the same teleport-enabled
ComboBox, targeting a local element in its scrollable body. Tailwind utilities make the teleported list participate
in that body's layout, with a maximum height of `20rem`. The option list scrolls while search and the CTA remain
visible. The drawer footer stays outside this scroll area, so a long menu cannot cover its buttons.

Real Chromium measurements at 1440 × 1100, using the actual drawer and actual `FlowBlockEditor.vue` with synthetic
data, confirmed identical triggers: 40px height, 8px radius, 14px normal-weight text and 10px/12px padding.
Both open lists have a 6px radius and the same background. Option rows match at 36px height, 14px text and 8px/12px
padding. Group headings match at 12px medium-weight text with 8px/12px/4px padding.

Template groups are ordered as Sistema / System, Atributos del contacto / Attributes of the contact,
Atributos de la conversación / Attributes of the conversation, and Citas de Captain / Captain appointments.
Flow retains its existing save-target labels and writable-target filtering.

## Verification

- Template Vitest folder: 285 tests passed across 25 files, including new/edit/copy selector coverage.
- ESLint and Prettier passed for changed Vue, JavaScript and translation files.
- Browser assertions compared trigger/option/group appearance, verified long-list scrolling and no footer overlap.
- Captures: `docs-crm/capturas/plantilla-editar-copia-variables.png` (list open) and
  `docs-crm/capturas/flow-picker-referencia.png`, in the sibling documentation directory.
- Each capture run used one browser instance. Browser and preview server were closed; temporary preset files removed.
