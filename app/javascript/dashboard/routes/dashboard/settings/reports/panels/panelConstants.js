import { startOfDay, endOfDay, subDays } from 'date-fns';
import { utcToZonedTime, zonedTimeToUtc } from 'date-fns-tz';

export const EDITOR_STEPS = ['CHOOSE', 'GROUP', 'FILTER', 'PREVIEW'];
export const PANEL_TYPES = [
  { value: 'metric', icon: 'i-lucide-hash' },
  { value: 'chart', icon: 'i-lucide-chart-column' },
  { value: 'table', icon: 'i-lucide-table' },
];
export const CHART_GROUPS = ['day', 'week', 'month'];
export const PREVIEW_DEBOUNCE_MS = 600;

export const DATE_PRESETS = [
  { value: 'today', labelKey: 'REPORT_PANELS.DATE_PRESETS.TODAY' },
  { value: 'yesterday', labelKey: 'REPORT_PANELS.DATE_PRESETS.YESTERDAY' },
  { value: 'last_7_days', labelKey: 'REPORT_PANELS.DATE_PRESETS.LAST_7_DAYS' },
  {
    value: 'last_30_days',
    labelKey: 'REPORT_PANELS.DATE_PRESETS.LAST_30_DAYS',
  },
  { value: 'custom', labelKey: 'REPORT_PANELS.DATE_PRESETS.CUSTOM' },
];

export const METRIC_OPTIONS = [
  'conversations_count',
  'unique_contacts_count',
  'contacts_count',
  'incoming_messages_count',
  'outgoing_messages_count',
  'avg_first_response_time',
  'avg_resolution_time',
  'reply_time',
  'resolutions_count',
];

export const METRIC_SOURCES = [
  { value: 'preset', labelKey: 'REPORT_PANELS.METRIC_SOURCES.PRESET' },
  {
    value: 'aggregation',
    labelKey: 'REPORT_PANELS.METRIC_SOURCES.AGGREGATION',
  },
];

export const AGGREGATION_OPS = [
  { value: 'count', labelKey: 'REPORT_PANELS.AGGREGATIONS.COUNT' },
  { value: 'sum', labelKey: 'REPORT_PANELS.AGGREGATIONS.SUM' },
  { value: 'avg', labelKey: 'REPORT_PANELS.AGGREGATIONS.AVG' },
  { value: 'min', labelKey: 'REPORT_PANELS.AGGREGATIONS.MIN' },
  { value: 'max', labelKey: 'REPORT_PANELS.AGGREGATIONS.MAX' },
];

export const AGGREGATION_ENTITIES = [
  {
    value: 'conversations',
    labelKey: 'REPORT_PANELS.AGGREGATION_ENTITIES.CONVERSATIONS',
  },
  {
    value: 'contacts',
    labelKey: 'REPORT_PANELS.AGGREGATION_ENTITIES.CONTACTS',
  },
];

export const TABLE_KINDS = [
  { value: 'pivot', labelKey: 'REPORT_PANELS.EDITOR.TYPES.TABLE' },
  {
    value: 'conversations',
    labelKey: 'REPORT_PANELS.TABLE_KINDS.CONVERSATIONS',
  },
  {
    value: 'contacts',
    labelKey: 'REPORT_PANELS.TABLE_KINDS.CONTACTS',
  },
];

export const TABLE_COLUMN_OPTIONS = {
  conversations: [
    'id',
    'contact_name',
    'status',
    'priority',
    'labels',
    'inbox',
    'assignee',
    'created_at',
    'last_activity_at',
  ],
  contacts: [
    'name',
    'phone_number',
    'email',
    'document_number',
    'labels',
    'conversations_count',
    'assignee',
    'inbox',
    'created_at',
    'last_activity_at',
    'id',
  ],
  pivot: [
    'rank',
    'name',
    'conversations_count',
    'resolved_conversations_count',
  ],
};

export const DEFAULT_TABLE_COLUMNS = {
  conversations: [
    'id',
    'contact_name',
    'status',
    'assignee',
    'inbox',
    'created_at',
  ],
  contacts: [
    'name',
    'phone_number',
    'email',
    'assignee',
    'inbox',
    'conversations_count',
    'last_activity_at',
  ],
  pivot: TABLE_COLUMN_OPTIONS.pivot,
};

/** Prefix for custom-attribute columns stored in widget.columns */
export const CA_COLUMN_PREFIX = 'ca:';
/** Contact custom attributes in pivot measures */
export const CONTACT_CA_COLUMN_PREFIX = 'contact_ca:';

/**
 * Pivot measure columns bake the aggregation into the column id so Count(ventas)
 * and Sum(ventas) can both be selected: `ca:ventas__count`, `ca:ventas__sum`.
 * Attribute keys themselves must not end with `__{op}` (Chatwoot keys are simple).
 */
export const MEASURE_OPS = ['count', 'sum', 'avg', 'min', 'max'];
export const MEASURE_SEP = '__';
/** Pivot: measure__pv__{urlencoded value} */
export const PIVOT_SEP = '__pv__';
export const MAX_PIVOT_VALUES = 12;
/** Attr types eligible as pivot column dimension (Excel “Columnas”) */
export const PIVOT_COLUMN_ATTR_TYPES = new Set(['list', 'text']);

/** Parse ca:/contact_ca: column → attrKey, op, optional eq filter */
export const parseCustomAttributeColumn = key => {
  const empty = {
    attrKey: null,
    op: null,
    contact: false,
  };
  if (typeof key !== 'string') return empty;

  let contact = false;
  let rest = null;
  if (key.startsWith(CONTACT_CA_COLUMN_PREFIX)) {
    contact = true;
    rest = key.slice(CONTACT_CA_COLUMN_PREFIX.length);
  } else if (key.startsWith(CA_COLUMN_PREFIX)) {
    rest = key.slice(CA_COLUMN_PREFIX.length);
  } else {
    return empty;
  }

  for (let i = 0; i < MEASURE_OPS.length; i += 1) {
    const op = MEASURE_OPS[i];
    const suffix = `${MEASURE_SEP}${op}`;
    if (rest.endsWith(suffix) && rest.length > suffix.length) {
      return {
        attrKey: rest.slice(0, -suffix.length),
        op,
        contact,
      };
    }
  }

  return {
    attrKey: rest,
    op: null,
    contact,
  };
};

export const isConversationCustomAttributeColumn = key =>
  typeof key === 'string' && key.startsWith(CA_COLUMN_PREFIX);

export const isContactCustomAttributeColumn = key =>
  typeof key === 'string' && key.startsWith(CONTACT_CA_COLUMN_PREFIX);

export const isCustomAttributeColumn = key =>
  isConversationCustomAttributeColumn(key) ||
  isContactCustomAttributeColumn(key);

/** Strip ca:/contact_ca: and optional __{op} → attribute_key */
export const customAttributeKeyFromColumn = key =>
  parseCustomAttributeColumn(key).attrKey;

export const measureOpFromColumn = key => {
  if (!isCustomAttributeColumn(key)) return null;
  return parseCustomAttributeColumn(key).op;
};

export const customAttributeColumnKey = attributeKey =>
  `${CA_COLUMN_PREFIX}${attributeKey}`;

export const contactCustomAttributeColumnKey = attributeKey =>
  `${CONTACT_CA_COLUMN_PREFIX}${attributeKey}`;

/** Pivot measure id with an explicit aggregation. */
export const customAttributeMeasureColumnKey = (
  attributeKey,
  op,
  { contact = false } = {}
) =>
  `${contact ? CONTACT_CA_COLUMN_PREFIX : CA_COLUMN_PREFIX}${attributeKey}${MEASURE_SEP}${op}`;

export const isPivotColumnKey = key =>
  typeof key === 'string' && key.includes(PIVOT_SEP);

export const parsePivotColumnKey = key => {
  if (!isPivotColumnKey(key)) return null;
  const idx = key.indexOf(PIVOT_SEP);
  const measure = key.slice(0, idx);
  const encoded = key.slice(idx + PIVOT_SEP.length);
  const value = decodeURIComponent(encoded);
  return { measure, value, encoded };
};

export const pivotColumnKey = (measure, value) => {
  const encoded = encodeURIComponent(value).replace(
    /[!'()*~]/g,
    char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`
  );
  return `${measure}${PIVOT_SEP}${encoded}`;
};

export const defaultPivotConfig = (row = 'agent') => ({
  row_attribute: row,
  column_attribute: '',
  column_values: [],
  show_row_totals: true,
});

/** Identity / label columns kept on the left of a pivot table */
export const PIVOT_IDENTITY_COLUMNS = new Set(['rank', 'name', 'id']);

export const SUMMABLE_CUSTOM_TYPES = new Set(['number', 'currency', 'percent']);

/** Normalize CA display type (API may send int enum or string). */
export const normalizeAttrDisplayType = attr => {
  const map = {
    0: 'text',
    1: 'number',
    2: 'currency',
    3: 'percent',
    4: 'link',
    5: 'date',
    6: 'list',
    7: 'checkbox',
    8: 'datetime',
  };
  const raw =
    attr?.attributeDisplayType ?? attr?.attribute_display_type ?? 'text';
  if (typeof raw === 'number') return map[raw] || 'text';
  return String(raw);
};

/** Measure operations available for each attribute type */
export const measureOpsForAttrType = type => {
  if (SUMMABLE_CUSTOM_TYPES.has(type)) {
    return ['count', 'sum', 'avg', 'min', 'max'];
  }
  // Non-numeric: only count of conversations/contacts where the attr is set / non-empty
  return ['count'];
};

/**
 * Parse number/currency/percent CA values that may use locale separators
 * ("1000,00", "1.000,50", "1,000.50") or currency symbols ("$10").
 * Returns null when the value cannot be interpreted as a finite number.
 */
export const parseLocaleNumber = value => {
  if (value == null || value === '') return null;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  let str = String(value)
    .trim()
    .replace(/[^\d,.-]/g, '');
  if (!str || str === '-' || str === '.' || str === ',') return null;

  if (str.includes(',') && str.includes('.')) {
    if (str.lastIndexOf(',') > str.lastIndexOf('.')) {
      // European: 1.000,50
      str = str.replace(/\./g, '').replace(',', '.');
    } else {
      // US: 1,000.50
      str = str.replace(/,/g, '');
    }
  } else if (str.includes(',')) {
    const parts = str.split(',');
    if (parts.length === 2 && parts[1].length >= 1 && parts[1].length <= 2) {
      // Decimal comma: 1000,00 / 10,5
      str = str.replace(',', '.');
    } else {
      // Thousands commas: 1,000 / 1,000,000
      str = str.replace(/,/g, '');
    }
  }

  const num = Number(str);
  return Number.isFinite(num) ? num : null;
};

/** Format numeric CA cells/footers; currency always shown with `$`. */
export const formatNumericAttribute = (value, type) => {
  const num = parseLocaleNumber(value);
  if (num == null) return value == null || value === '' ? '—' : String(value);

  if (type === 'currency') {
    return `$${num.toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
  if (type === 'percent') {
    return `${num.toLocaleString(undefined, {
      maximumFractionDigits: 2,
    })}%`;
  }
  return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
};

export const ROW_GRANULARITIES = ['day', 'week', 'month'];
export const TOP_N_LIMITS = [null, 5, 10, 20];
export const MEASURE_DISPLAYS = ['value', 'row_percent', 'column_percent'];
export const COLUMN_FORMAT_TYPES = ['', 'currency', 'percent', 'integer'];
export const COLUMN_DECIMALS = [0, 1, 2];
export const PIVOT_SYSTEM_MEASURES = new Set([
  'conversations_count',
  'resolved_conversations_count',
]);

export const isAdditiveMeasure = column =>
  PIVOT_SYSTEM_MEASURES.has(column) ||
  ['count', 'sum'].includes(measureOpFromColumn(column));

/** Keep dependent settings attached when a measure changes; drop removed keys. */
export const cleanTableOptions = (
  widget,
  previous = null,
  replacement = null
) => {
  const columns = widget.columns || [];
  const measures = columns.filter(key => !PIVOT_IDENTITY_COLUMNS.has(key));
  const remap = key => {
    const parsed = parsePivotColumnKey(key);
    const base = parsed?.measure || key;
    const next = base === previous ? replacement : base;
    if (!next || !columns.includes(next)) return null;
    if (parsed && !widget.pivot?.column_attribute) return null;
    return parsed ? pivotColumnKey(next, parsed.value) : next;
  };
  ['column_formats', 'measure_display'].forEach(option => {
    if (!widget[option]) return;
    widget[option] = Object.fromEntries(
      Object.entries(widget[option]).flatMap(([key, value]) => {
        const next = remap(key);
        if (!next || !measures.includes(next)) return [];
        if (
          option === 'measure_display' &&
          value !== 'value' &&
          !isAdditiveMeasure(next)
        )
          return [];
        return [[next, value]];
      })
    );
  });
  if (widget.sort) {
    const column = remap(widget.sort.column);
    if (column) widget.sort = { ...widget.sort, column };
    else delete widget.sort;
  }
  if (widget.top_n) {
    const column = remap(widget.top_n.column);
    if (column && !PIVOT_IDENTITY_COLUMNS.has(column)) {
      widget.top_n = {
        ...widget.top_n,
        column,
        include_others:
          widget.top_n.include_others &&
          !measures.some(isContactCustomAttributeColumn),
      };
    } else delete widget.top_n;
  }
  if (widget.table_kind !== 'pivot') {
    ['sort', 'top_n', 'column_formats', 'measure_display'].forEach(option => {
      delete widget[option];
    });
  }
  return widget;
};

export const formatPanelMeasure = (value, config) => {
  const number = parseLocaleNumber(value);
  if (number == null) return '—';
  const decimals = config.decimals ?? (config.type === 'integer' ? 0 : 2);
  const formatted = number.toLocaleString(undefined, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  if (config.type === 'currency')
    return `${config.currency_symbol ?? '$'}${formatted}`;
  if (config.type === 'percent') return `${formatted}%`;
  return formatted;
};

export const defaultColumnsForTableKind = kind => {
  if (DEFAULT_TABLE_COLUMNS[kind]) return [...DEFAULT_TABLE_COLUMNS[kind]];
  if (TABLE_COLUMN_OPTIONS[kind]) return [...TABLE_COLUMN_OPTIONS[kind]];
  return [];
};

export const resolveTableColumns = (kind, columns) => {
  const systemAllowed = TABLE_COLUMN_OPTIONS[kind] || [];
  if (!systemAllowed.length) return [];
  const selected = Array.isArray(columns)
    ? columns.filter(
        key => systemAllowed.includes(key) || isCustomAttributeColumn(key)
      )
    : [];
  return selected.length ? selected : defaultColumnsForTableKind(kind);
};

/** Prefix for contact-entity filters (labels, etc.) routed to Contacts::FilterService */
export const CONTACT_FILTER_PREFIX = 'contact:';
export const CONTACT_ATTR_PREFIX = 'contact_ca:';

export const MULTI_SELECT_SYSTEM_KEYS = new Set(['assignee_id', 'inbox_id']);

export const newWidgetId = () =>
  `w_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

export const defaultMetricWidget = () => ({
  id: newWidgetId(),
  type: 'metric',
  title: '',
  source: 'preset',
  metric: 'conversations_count',
  aggregation_op: 'count',
  aggregation_field: '',
  aggregation_group_field: '',
  aggregation_entity: 'conversations',
  scope_type: 'account',
  scope_id: null,
});

export const defaultChartWidget = () => ({
  id: newWidgetId(),
  type: 'chart',
  title: '',
  source: 'preset',
  metric: 'conversations_count',
  aggregation_op: 'count',
  aggregation_field: '',
  aggregation_group_field: '',
  aggregation_entity: 'conversations',
  scope_type: 'account',
  scope_id: null,
  chart_kind: 'bar',
  group_by: 'day',
});

export const defaultTableWidget = () => ({
  id: newWidgetId(),
  type: 'table',
  title: '',
  table_kind: 'pivot',
  columns: defaultColumnsForTableKind('pivot'),
  column_aggregations: {},
  pivot: defaultPivotConfig(),
});

export const emptyPanel = () => ({
  name: '',
  description: '',
  date_preset: 'last_7_days',
  custom_since: null,
  custom_until: null,
  date_attribute: '',
  business_hours: false,
  favorite: false,
  filters: [],
  widgets: [defaultMetricWidget(), defaultChartWidget()],
});

/** Conversation date/datetime CAs eligible as panel date axis (`ca:key`). */
export const DATE_AXIS_ATTR_TYPES = new Set(['date', 'datetime']);

/** Map saved panel date_preset → WootDatePicker rangeType. */
export const panelPresetToRangeType = preset => {
  switch (preset) {
    case 'last_30_days':
      return 'last30days';
    case 'custom':
    case 'today':
    case 'yesterday':
      // Picker has no today/yesterday presets — show as custom with exact dates.
      return 'custom';
    case 'last_7_days':
    default:
      return 'last7days';
  }
};

export const panelPickerRangeToUnix = (dates, timezone = 'UTC') => [
  Math.floor(zonedTimeToUtc(startOfDay(dates[0]), timezone).getTime() / 1000),
  Math.floor(zonedTimeToUtc(endOfDay(dates[1]), timezone).getTime() / 1000),
];

/** Resolve the saved range into UTC instants in the effective reporting timezone. */
export const panelRangeToDates = panel => {
  if (
    panel?.date_preset === 'custom' &&
    panel.custom_since != null &&
    panel.custom_until != null
  ) {
    return [
      new Date(panel.custom_since * 1000),
      new Date(panel.custom_until * 1000),
    ];
  }

  const timezone = panel?.reporting_timezone || 'UTC';
  const today = utcToZonedTime(new Date(), timezone);
  let firstDay = today;
  let lastDay = today;
  switch (panel?.date_preset) {
    case 'today':
      break;
    case 'yesterday':
      firstDay = subDays(today, 1);
      lastDay = firstDay;
      break;
    case 'last_30_days':
      firstDay = subDays(today, 29);
      break;
    case 'last_7_days':
    default:
      firstDay = subDays(today, 6);
  }
  const [since, until] = panelPickerRangeToUnix([firstDay, lastDay], timezone);
  return [new Date(since * 1000), new Date(until * 1000)];
};

// The shared picker uses local Date fields as calendar days, not UTC instants.
export const panelReportingToday = timezone =>
  utcToZonedTime(new Date(), timezone || 'UTC');

export const panelRangeToPickerDates = panel =>
  panelRangeToDates(panel).map(date =>
    utcToZonedTime(date, panel?.reporting_timezone || 'UTC')
  );
