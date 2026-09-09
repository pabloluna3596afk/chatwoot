export const GUARD_RULE_TYPES = [
  'require_attributes_on_status',
  'if_attribute_then_require',
  'require_reason_on_status',
  'forbid_status_if',
  'require_assignee_on_status',
];

export const emptyCondition = () => ({
  attribute_key: 'status',
  filter_operator: 'equal_to',
  values: [],
  query_operator: null,
  custom_attribute_type: '',
});

export const emptyConfigForType = type => {
  switch (type) {
    case 'require_attributes_on_status':
      return {
        status: 'resolved',
        attribute_keys: [],
        contact_attribute_keys: [],
        attribute_category_keys: [],
        contact_attribute_category_keys: [],
      };
    case 'if_attribute_then_require':
      return {
        when_attribute: '',
        when_attribute_model: 'conversation',
        when_values: [],
        require_attribute_keys: [],
        require_contact_attribute_keys: [],
        require_attribute_category_keys: [],
        require_contact_attribute_category_keys: [],
        on_status: 'resolved',
      };
    case 'require_reason_on_status':
      return {
        statuses: ['pending', 'snoozed'],
        require_private_note: true,
        reason_attribute_key: '',
      };
    case 'forbid_status_if':
      return { status: 'resolved', label: '' };
    case 'require_assignee_on_status':
      return { status: 'open', require_team_or_agent: true };
    default:
      return {};
  }
};

export const BUSINESS_RULE_PRESETS = [
  {
    id: 'require_on_resolve',
    family: 'guard',
    type: 'require_attributes_on_status',
    nameKey: 'BUSINESS_RULES.PRESETS.REQUIRE_ON_RESOLVE',
    descriptionKey: 'BUSINESS_RULES.PRESETS.REQUIRE_ON_RESOLVE_DESC',
    defaults: {
      type: 'require_attributes_on_status',
      enabled: false,
      conditions: [],
      config: {
        status: 'resolved',
        attribute_keys: [],
        contact_attribute_keys: [],
        attribute_category_keys: [],
        contact_attribute_category_keys: [],
      },
    },
  },
  {
    id: 'if_x_require_yz',
    family: 'guard',
    type: 'if_attribute_then_require',
    nameKey: 'BUSINESS_RULES.PRESETS.IF_X_REQUIRE_YZ',
    descriptionKey: 'BUSINESS_RULES.PRESETS.IF_X_REQUIRE_YZ_DESC',
    defaults: {
      type: 'if_attribute_then_require',
      enabled: false,
      conditions: [],
      config: {
        when_attribute: '',
        when_attribute_model: 'conversation',
        when_values: [],
        require_attribute_keys: [],
        require_contact_attribute_keys: [],
        require_attribute_category_keys: [],
        require_contact_attribute_category_keys: [],
        on_status: 'resolved',
      },
    },
  },
  {
    id: 'motivo_al_posponer',
    family: 'guard',
    type: 'require_reason_on_status',
    nameKey: 'BUSINESS_RULES.PRESETS.MOTIVO_POSPONER',
    descriptionKey: 'BUSINESS_RULES.PRESETS.MOTIVO_POSPONER_DESC',
    defaults: {
      type: 'require_reason_on_status',
      enabled: false,
      conditions: [],
      config: {
        statuses: ['pending', 'snoozed'],
        require_private_note: true,
        reason_attribute_key: '',
      },
    },
  },
  {
    id: 'forbid_resolve_label',
    family: 'guard',
    type: 'forbid_status_if',
    nameKey: 'BUSINESS_RULES.PRESETS.FORBID_RESOLVE_LABEL',
    descriptionKey: 'BUSINESS_RULES.PRESETS.FORBID_RESOLVE_LABEL_DESC',
    defaults: {
      type: 'forbid_status_if',
      enabled: false,
      conditions: [],
      config: { status: 'resolved', label: '' },
    },
  },
  {
    id: 'require_assignee_on_open',
    family: 'guard',
    type: 'require_assignee_on_status',
    nameKey: 'BUSINESS_RULES.PRESETS.REQUIRE_ASSIGNEE_ON_OPEN',
    descriptionKey: 'BUSINESS_RULES.PRESETS.REQUIRE_ASSIGNEE_ON_OPEN_DESC',
    defaults: {
      type: 'require_assignee_on_status',
      enabled: false,
      conditions: [],
      config: { status: 'open', require_team_or_agent: true },
    },
  },
];

export const TIME_RULE_PRESETS = [
  {
    id: 'post_compra_n_dias',
    family: 'time',
    nameKey: 'BUSINESS_RULES.PRESETS.POST_COMPRA',
    descriptionKey: 'BUSINESS_RULES.PRESETS.POST_COMPRA_DESC',
    // Without this, activating the preset created a rule pointing at
    // `fecha_venta` with nothing to ever create that attribute — the rule
    // looked active but could never fire. The admin now picks an existing
    // date attribute or names a new one before the rule is created.
    requiresAttributes: [
      {
        attributeKey: 'fecha_venta',
        attributeDisplayNameKey:
          'BUSINESS_RULES.PRESETS.POST_COMPRA_ATTRIBUTE_NAME',
        attributeModel: 'conversation_attribute',
        attributeDisplayType: 'date',
        // A completed sale — groups with future commerce recipes (carrito
        // abandonado, recompra, etc.) rather than sitting uncategorized.
        categoryKey: 'BUSINESS_RULES.PRESETS.CATEGORY_VENTAS',
      },
    ],
    defaults: {
      event_name: 'time_triggered',
      schedule: {
        kind: 'days_since_attribute',
        attribute_key: 'fecha_venta',
        days: 15,
      },
      conditions: [],
      actions: [{ action_name: 'add_label', action_params: ['seguimiento'] }],
    },
  },
  {
    id: 'followup_sin_respuesta',
    family: 'time',
    nameKey: 'BUSINESS_RULES.PRESETS.FOLLOWUP_24H',
    descriptionKey: 'BUSINESS_RULES.PRESETS.FOLLOWUP_24H_DESC',
    defaults: {
      event_name: 'time_triggered',
      schedule: { kind: 'hours_since_last_outgoing', hours: 24 },
      conditions: [],
      actions: [
        {
          action_name: 'send_message',
          action_params: ['Hola {{contact.name}}, ¿qué pasó? ¿Te animaste?'],
        },
      ],
    },
  },
  {
    id: 'seguimiento_30d',
    family: 'time',
    nameKey: 'BUSINESS_RULES.PRESETS.SEGUIMIENTO_30D',
    descriptionKey: 'BUSINESS_RULES.PRESETS.SEGUIMIENTO_30D_DESC',
    // `fecha_seguimiento` appears both in the schedule and in the
    // update_conversation_custom_attribute action below — activateTimePreset
    // substitutes the resolved key everywhere it appears, not just here.
    requiresAttributes: [
      {
        attributeKey: 'fecha_seguimiento',
        attributeDisplayNameKey:
          'BUSINESS_RULES.PRESETS.SEGUIMIENTO_30D_ATTRIBUTE_NAME',
        attributeModel: 'conversation_attribute',
        attributeDisplayType: 'date',
        // A general nudge on any open conversation, not tied to a completed
        // sale — a distinct bucket from the post-purchase one above.
        categoryKey: 'BUSINESS_RULES.PRESETS.CATEGORY_SEGUIMIENTO',
      },
    ],
    defaults: {
      event_name: 'time_triggered',
      schedule: {
        kind: 'days_since_attribute',
        attribute_key: 'fecha_seguimiento',
        days: 30,
      },
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
          query_operator: null,
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'send_message',
          action_params: [
            'Hola {{contact.name}}, te escribimos para dar seguimiento. ¿Cómo va todo?',
          ],
        },
        {
          action_name: 'update_conversation_custom_attribute',
          action_params: [
            {
              attribute_key: 'fecha_seguimiento',
              value: '{{ date.today }}',
            },
          ],
        },
        { action_name: 'notify_assignee', action_params: [] },
      ],
    },
  },
];

// Contact-based recipes (Automations::ContactBasedRuleRunner) — reach
// contacts with no open conversation via a WhatsApp template. Mirrors the
// examples already documented in that runner's own file header.
export const CONTACT_RULE_PRESETS = [
  {
    id: 'cumpleanos_descuento',
    family: 'contact',
    nameKey: 'BUSINESS_RULES.CONTACT_PRESETS.CUMPLEANOS.NAME',
    descriptionKey: 'BUSINESS_RULES.CONTACT_PRESETS.CUMPLEANOS.DESC',
    dateSource: 'contact_attribute',
    recurrence: 'yearly',
    attributeSuggestion: {
      attributeKey: 'cumpleanos',
      attributeDisplayNameKey:
        'BUSINESS_RULES.CONTACT_PRESETS.CUMPLEANOS.ATTRIBUTE_NAME',
      attributeModel: 'contact_attribute',
      attributeDisplayType: 'date',
    },
    dayOptions: [
      {
        id: 'on',
        days: 0,
        relativeTo: 'on',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.SAME_DAY',
      },
      {
        id: '3_before',
        days: 3,
        relativeTo: 'before',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_BEFORE',
        labelCount: 3,
      },
      {
        id: '7_before',
        days: 7,
        relativeTo: 'before',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_BEFORE',
        labelCount: 7,
      },
    ],
  },
  {
    id: 'aniversario_cliente',
    family: 'contact',
    nameKey: 'BUSINESS_RULES.CONTACT_PRESETS.ANIVERSARIO.NAME',
    descriptionKey: 'BUSINESS_RULES.CONTACT_PRESETS.ANIVERSARIO.DESC',
    dateSource: 'contact_attribute',
    recurrence: 'yearly',
    attributeSuggestion: {
      attributeKey: 'fecha_alta',
      attributeDisplayNameKey:
        'BUSINESS_RULES.CONTACT_PRESETS.ANIVERSARIO.ATTRIBUTE_NAME',
      attributeModel: 'contact_attribute',
      attributeDisplayType: 'date',
    },
    dayOptions: [
      {
        id: 'on',
        days: 0,
        relativeTo: 'on',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.SAME_DAY',
      },
      {
        id: '3_before',
        days: 3,
        relativeTo: 'before',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_BEFORE',
        labelCount: 3,
      },
    ],
  },
  {
    id: 'recompra_reposicion',
    family: 'contact',
    nameKey: 'BUSINESS_RULES.CONTACT_PRESETS.RECOMPRA.NAME',
    descriptionKey: 'BUSINESS_RULES.CONTACT_PRESETS.RECOMPRA.DESC',
    dateSource: 'contact_attribute',
    recurrence: 'once',
    attributeSuggestion: {
      attributeKey: 'fecha_venta',
      attributeDisplayNameKey:
        'BUSINESS_RULES.CONTACT_PRESETS.RECOMPRA.ATTRIBUTE_NAME',
      attributeModel: 'contact_attribute',
      attributeDisplayType: 'date',
    },
    dayOptions: [
      {
        id: '30_after',
        days: 30,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 30,
      },
      {
        id: '60_after',
        days: 60,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 60,
      },
      {
        id: '90_after',
        days: 90,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 90,
      },
    ],
  },
  {
    id: 'reactivar_inactivos',
    family: 'contact',
    nameKey: 'BUSINESS_RULES.CONTACT_PRESETS.REACTIVAR.NAME',
    descriptionKey: 'BUSINESS_RULES.CONTACT_PRESETS.REACTIVAR.DESC',
    dateSource: 'last_activity',
    recurrence: 'once',
    // No attributeSuggestion — last_activity reads a column, not a custom
    // attribute, so the dialog skips the attribute picker for this one.
    dayOptions: [
      {
        id: '30_after',
        days: 30,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 30,
      },
      {
        id: '60_after',
        days: 60,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 60,
      },
      {
        id: '90_after',
        days: 90,
        relativeTo: 'after',
        labelKey: 'BUSINESS_RULES.CONTACT_PRESETS.DAY_OPTIONS.DAYS_AFTER',
        labelCount: 90,
      },
    ],
  },
];

export const newRuleId = () =>
  `br_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;

export const summarizeRule = (rule, t) => {
  if (!rule) return '';
  const config = rule.config || {};
  const status =
    config.status ||
    config.on_status ||
    (Array.isArray(config.statuses) ? config.statuses.join(', ') : '');
  const parts = [];
  if (status) {
    parts.push(
      t('BUSINESS_RULES.SUMMARY.STATUS', {
        status: t(`BUSINESS_RULES.STATUSES.${status}`, status),
      })
    );
  }
  const catCount =
    (config.attribute_category_keys || []).length +
    (config.contact_attribute_category_keys || []).length +
    (config.require_attribute_category_keys || []).length +
    (config.require_contact_attribute_category_keys || []).length;
  const keyCount =
    (config.attribute_keys || []).length +
    (config.contact_attribute_keys || []).length +
    (config.require_attribute_keys || []).length +
    (config.require_contact_attribute_keys || []).length;
  if (catCount) {
    parts.push(t('BUSINESS_RULES.SUMMARY.CATEGORIES', { count: catCount }));
  }
  if (keyCount) {
    parts.push(t('BUSINESS_RULES.SUMMARY.KEYS', { count: keyCount }));
  }
  if ((rule.conditions || []).length) {
    parts.push(
      t('BUSINESS_RULES.SUMMARY.CONDITIONS', {
        count: rule.conditions.length,
      })
    );
  }
  if (config.label) {
    parts.push(t('BUSINESS_RULES.SUMMARY.LABEL', { label: config.label }));
  }
  return parts.join(' · ') || t('BUSINESS_RULES.SUMMARY.EMPTY');
};
