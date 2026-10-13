<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ReportHeader from '../components/ReportHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PanelWidgetCard from './components/PanelWidgetCard.vue';
import { validateSingleFilter } from 'dashboard/helper/validations';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import { useConversationFilterContext } from 'dashboard/components-next/filter/provider';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { buildAttributesFilterTypes } from 'dashboard/components-next/filter/helper/filterHelper';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import SavedReportPanelsAPI from 'dashboard/api/savedReportPanels';
import {
  DATE_PRESETS,
  METRIC_OPTIONS,
  METRIC_SOURCES,
  AGGREGATION_OPS,
  AGGREGATION_ENTITIES,
  TABLE_KINDS,
  CONTACT_ATTR_PREFIX,
  CONTACT_FILTER_PREFIX,
  MULTI_SELECT_SYSTEM_KEYS,
  SUMMABLE_CUSTOM_TYPES,
  SUMMARY_TABLE_KINDS,
  MAX_PIVOT_VALUES,
  defaultPivotConfig,
  defaultColumnsForTableKind,
  defaultChartWidget,
  defaultMetricWidget,
  defaultTableWidget,
  emptyPanel,
  panelRangeToPickerDates,
  panelPickerRangeToUnix,
  resolveTableColumns,
  normalizeAttrDisplayType,
  customAttributeColumnKey,
  DATE_AXIS_ATTR_TYPES,
  CA_COLUMN_PREFIX,
  EDITOR_STEPS,
  PANEL_TYPES,
  CHART_GROUPS,
  PREVIEW_DEBOUNCE_MS,
} from './panelConstants';
import PanelTablePivotBuilder from './components/PanelTablePivotBuilder.vue';
import subDays from 'date-fns/subDays';
import { format, isValid, parseISO } from 'date-fns';

const props = defineProps({
  isNew: { type: Boolean, default: false },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountScopedRoute, currentAccount } = useAccount();
const panelTimezone = ref(null);
const reportingTimezone = computed(
  () => panelTimezone.value || currentAccount.value.reporting_timezone || 'UTC'
);
const { filterTypes } = useConversationFilterContext();
const contactAttributes = useMapGetter('attributes/getContactAttributes');
const conversationAttributes = useMapGetter(
  'attributes/getConversationAttributes'
);
const labels = useMapGetter('labels/getLabels');
const { getOperatorTypes, presenceOperators } = useOperators();

const saving = ref(false);
const form = ref({ ...emptyPanel(), widgets: [defaultMetricWidget()] });
const step = ref(0);
const selectedId = ref(form.value.widgets[0].id);
const selectedWidget = computed(() =>
  form.value.widgets.find(widget => widget.id === selectedId.value)
);
const selectedIndex = computed(() =>
  form.value.widgets.findIndex(widget => widget.id === selectedId.value)
);
const ready = ref(false);
const loading = ref(true);
const loadFailed = ref(false);
const preview = ref(null);
const previewWidgets = ref([]);
const previewRunning = ref(false);
const previewError = ref(false);
const previewRequest = useAbortableRequest();
let previewVersion = 0;
const groupOptions = computed(() =>
  CHART_GROUPS.map(value => ({
    value,
    label: t(`REPORT_PANELS.EDITOR.GROUPS.${value.toUpperCase()}`),
  }))
);
const widgetOptions = computed(() =>
  form.value.widgets.map((widget, index) => ({
    value: widget.id,
    label:
      widget.title ||
      `${t(`REPORT_PANELS.EDITOR.TYPES.${widget.type.toUpperCase()}`)} ${index + 1}`,
  }))
);
const attributeLabels = computed(() =>
  Object.fromEntries([
    ...(conversationAttributes.value || []).flatMap(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      const label = attr.attributeDisplayName || attr.attribute_display_name;
      return [
        [key, label],
        [`ca:${key}`, label],
      ];
    }),
    ...(contactAttributes.value || []).flatMap(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      const label = attr.attributeDisplayName || attr.attribute_display_name;
      return [
        [key, label],
        [`contact_ca:${key}`, label],
      ];
    }),
  ])
);
const attributeTypes = computed(() =>
  Object.fromEntries([
    ...(conversationAttributes.value || []).flatMap(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      const type = normalizeAttrDisplayType(attr);
      return [
        [key, type],
        [`ca:${key}`, type],
      ];
    }),
    ...(contactAttributes.value || []).flatMap(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      const type = normalizeAttrDisplayType(attr);
      return [
        [key, type],
        [`contact_ca:${key}`, type],
      ];
    }),
  ])
);
const resultById = computed(() =>
  Object.fromEntries(
    (preview.value?.widgets || []).map(result => [result.id, result])
  )
);
const uiFilters = ref([]);
const conditionsRef = useTemplateRef('conditionsRef');
const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const customDateValues = computed(() =>
  customDateRange.value.map(date =>
    isValid(date) ? format(date, 'yyyy-MM-dd') : ''
  )
);

const pageTitle = computed(() =>
  props.isNew ? t('REPORT_PANELS.CREATE') : t('REPORT_PANELS.EDIT')
);

const isCustomRange = computed(() => form.value.date_preset === 'custom');

const datePresetOptions = computed(() =>
  DATE_PRESETS.map(preset => ({
    value: preset.value,
    label: t(preset.labelKey),
  }))
);

const dateAttributeOptions = computed(() => {
  const created = {
    value: '',
    label: t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE_CREATED_AT'),
  };
  const attrs = (conversationAttributes.value || [])
    .filter(attr => DATE_AXIS_ATTR_TYPES.has(normalizeAttrDisplayType(attr)))
    .map(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      return {
        value: `${CA_COLUMN_PREFIX}${key}`,
        label: attr.attributeDisplayName || attr.attribute_display_name || key,
      };
    });
  return [created, ...attrs];
});

const metricOptions = computed(() =>
  METRIC_OPTIONS.map(metric => ({
    value: metric,
    label: t(`REPORT_PANELS.METRICS.${metric}`),
  }))
);

const metricSourceOptions = computed(() =>
  METRIC_SOURCES.map(item => ({
    value: item.value,
    label: t(item.labelKey),
  }))
);

const aggregationOpOptions = computed(() =>
  AGGREGATION_OPS.map(item => ({
    value: item.value,
    label: t(item.labelKey),
  }))
);

const aggregationEntityOptions = computed(() =>
  AGGREGATION_ENTITIES.map(item => ({
    value: item.value,
    label: t(item.labelKey),
  }))
);

const tableKindOptions = computed(() =>
  TABLE_KINDS.map(kind => ({
    value: kind.value,
    label: t(kind.labelKey),
  }))
);

const syncCustomDates = () => {
  if (!customDateRange.value.every(date => isValid(date))) {
    form.value.custom_since = null;
    form.value.custom_until = null;
    return;
  }
  [form.value.custom_since, form.value.custom_until] = panelPickerRangeToUnix(
    customDateRange.value,
    reportingTimezone.value
  );
};

const onPresetChange = () => {
  if (!isCustomRange.value) {
    form.value.custom_since = null;
    form.value.custom_until = null;
    return;
  }
  const [from, to] = panelRangeToPickerDates({
    date_preset: 'last_7_days',
    reporting_timezone: reportingTimezone.value,
  });
  customDateRange.value = [from, to];
  syncCustomDates();
};

const onCustomDateChange = (index, value) => {
  customDateRange.value[index] = parseISO(value);
  syncCustomDates();
};

// Group system / conversation custom / contact filters for the builder.
const panelFilterTypes = computed(() => {
  const types = filterTypes.value || [];
  const system = types
    .filter(item => item.attributeModel !== 'customAttributes')
    .map(item => {
      let next = { ...item };
      if (MULTI_SELECT_SYSTEM_KEYS.has(item.attributeKey)) {
        next = { ...next, inputType: 'multiSelect' };
      }
      if (item.attributeKey === 'labels') {
        next = {
          ...next,
          attributeName: t('REPORT_PANELS.FILTERS.CONVERSATION_LABELS'),
          label: t('REPORT_PANELS.FILTERS.CONVERSATION_LABELS'),
        };
      }
      return next;
    });
  const conversationCustom = types.filter(
    item => item.attributeModel === 'customAttributes'
  );
  const contactLabelsKey = `${CONTACT_FILTER_PREFIX}labels`;
  const contactLabels = {
    attributeKey: contactLabelsKey,
    value: contactLabelsKey,
    attributeName: t('REPORT_PANELS.FILTERS.CONTACT_LABELS'),
    label: t('REPORT_PANELS.FILTERS.CONTACT_LABELS'),
    inputType: 'multiSelect',
    options: (labels.value || []).map(label => ({
      id: label.title,
      name: label.title,
    })),
    dataType: 'text',
    filterOperators: presenceOperators.value,
    attributeModel: 'standard',
    customAttributeType: 'contact',
    sourceAttributeKey: 'labels',
  };
  const contactCustom = buildAttributesFilterTypes(
    contactAttributes.value || [],
    getOperatorTypes,
    'contact'
  ).map(item => {
    const keyed = `${CONTACT_ATTR_PREFIX}${item.attributeKey}`;
    return {
      ...item,
      attributeKey: keyed,
      value: keyed,
      sourceAttributeKey: item.attributeKey,
      customAttributeType: 'contact_attribute',
    };
  });

  const grouped = [];
  if (system.length) {
    grouped.push({
      value: '__system_attrs__',
      label: t('REPORT_PANELS.FILTERS.SYSTEM_ATTRIBUTES'),
      disabled: true,
    });
    grouped.push(...system);
  }
  if (conversationCustom.length) {
    grouped.push({
      value: '__custom_attrs__',
      label: t('REPORT_PANELS.FILTERS.CUSTOM_ATTRIBUTES'),
      disabled: true,
    });
    grouped.push(...conversationCustom);
  }
  grouped.push({
    value: '__contact_attrs__',
    label: t('REPORT_PANELS.FILTERS.CONTACT_ATTRIBUTES'),
    disabled: true,
  });
  grouped.push(contactLabels);
  if (contactCustom.length) {
    grouped.push({
      value: '__contact_custom_attrs__',
      label: t('REPORT_PANELS.FILTERS.CONTACT_CUSTOM_ATTRIBUTES'),
      disabled: true,
    });
    grouped.push(...contactCustom);
  }
  return grouped.length ? grouped : types;
});

const resolveFilterType = attributeKey =>
  panelFilterTypes.value.find(
    item => item.attributeKey === attributeKey || item.value === attributeKey
  );

const hasMixedFilterGroups = computed(() => {
  if (uiFilters.value.length < 2) return false;
  let hasConversation = false;
  let hasContact = false;
  uiFilters.value.forEach(filter => {
    const type = resolveFilterType(filter.attributeKey);
    if (
      type?.customAttributeType === 'contact_attribute' ||
      type?.customAttributeType === 'contact'
    ) {
      hasContact = true;
    } else {
      hasConversation = true;
    }
  });
  return hasConversation && hasContact;
});

const contactFilterLookupKey = filter => {
  if (filter.custom_attribute_type === 'contact_attribute') {
    return `${CONTACT_ATTR_PREFIX}${filter.attribute_key}`;
  }
  if (filter.custom_attribute_type === 'contact') {
    return `${CONTACT_FILTER_PREFIX}${filter.attribute_key}`;
  }
  return filter.attribute_key;
};

const hydrateFilterValues = (filter, types) => {
  const lookupKey = contactFilterLookupKey(filter);
  const type = types.find(
    item => item.attributeKey === lookupKey || item.value === lookupKey
  );
  const values = filter.values;
  if (!Array.isArray(values)) return values ?? [];
  if (!type) return values;

  if (type.inputType === 'multiSelect') {
    return values.map(id => {
      const option = type.options?.find(
        opt => opt.id === id || String(opt.id) === String(id)
      );
      return option || { id, name: String(id) };
    });
  }

  if (
    ['searchSelect', 'asyncSearchSelect', 'booleanSelect'].includes(
      type.inputType
    )
  ) {
    const id = values[0];
    const option = type.options?.find(
      opt => opt.id === id || String(opt.id) === String(id)
    );
    return option || { id, name: String(id) };
  }

  return values[0] ?? '';
};

const ensureWidgetDefaults = widget => {
  if (widget.type === 'metric' || widget.type === 'chart') {
    if (!widget.source) widget.source = 'preset';
    if (!widget.aggregation_op) widget.aggregation_op = 'count';
    if (widget.aggregation_field == null) widget.aggregation_field = '';
    if (widget.aggregation_group_field == null) {
      widget.aggregation_group_field = '';
    }
    if (!widget.aggregation_entity) widget.aggregation_entity = 'conversations';
  }
  if (widget.type === 'table' && !widget.column_aggregations) {
    widget.column_aggregations = {};
  }
  if (widget.type === 'table' && !widget.pivot) {
    widget.pivot = defaultPivotConfig();
  }
  return widget;
};

const loadExisting = async () => {
  if (props.isNew) return;
  try {
    const { data } = await SavedReportPanelsAPI.show(route.params.id);
    panelTimezone.value = data.reporting_timezone;
    form.value = {
      name: data.name,
      description: data.description || '',
      date_preset: data.date_preset,
      custom_since: data.custom_since,
      custom_until: data.custom_until,
      date_attribute: data.date_attribute || '',
      business_hours: data.business_hours,
      favorite: data.favorite,
      filters: data.filters || [],
      widgets: (data.widgets || []).map(ensureWidgetDefaults),
    };
    selectedId.value = form.value.widgets[0]?.id;
    if (data.date_preset === 'custom') {
      customDateRange.value = panelRangeToPickerDates(data);
    }
    const types = panelFilterTypes.value || [];
    uiFilters.value = (data.filters || []).map(filter => ({
      attributeKey: contactFilterLookupKey(filter),
      filterOperator: filter.filter_operator,
      values: hydrateFilterValues(filter, types),
      queryOperator: filter.query_operator || 'and',
    }));
  } catch {
    loadFailed.value = true;
    useAlert(t('REPORT_PANELS.ERRORS.LOAD'));
  }
};

const addFilter = () => {
  if (uiFilters.value.length >= 10) {
    useAlert(t('REPORT_PANELS.ERRORS.MAX_FILTERS'));
    return;
  }
  uiFilters.value.push({
    attributeKey: 'status',
    filterOperator: 'equal_to',
    values: [],
    queryOperator: 'and',
  });
};

const removeFilter = index => {
  uiFilters.value.splice(index, 1);
};

const addWidget = type => {
  if (form.value.widgets.length >= 12) {
    useAlert(t('REPORT_PANELS.ERRORS.MAX_WIDGETS'));
    return;
  }
  if (type === 'metric') form.value.widgets.push(defaultMetricWidget());
  else if (type === 'chart') form.value.widgets.push(defaultChartWidget());
  else form.value.widgets.push(defaultTableWidget());
  selectedId.value = form.value.widgets.at(-1).id;
  step.value = 0;
};

const removeWidget = index => {
  form.value.widgets.splice(index, 1);
  selectedId.value =
    form.value.widgets[Math.min(index, form.value.widgets.length - 1)]?.id;
};

const changeWidgetType = type => {
  const widget = selectedWidget.value;
  if (widget.type === type) return;
  const widgetFactories = {
    metric: defaultMetricWidget,
    chart: defaultChartWidget,
    table: defaultTableWidget,
  };
  const defaults = widgetFactories[type]();
  form.value.widgets[selectedIndex.value] = {
    ...defaults,
    ...(type !== 'table' && widget.type !== 'table' ? widget : {}),
    type,
    id: widget.id,
    title: widget.title,
  };
};

const moveWidget = (index, direction) => {
  const target = index + direction;
  if (target < 0 || target >= form.value.widgets.length) return;
  const widgets = [...form.value.widgets];
  const [item] = widgets.splice(index, 1);
  widgets.splice(target, 0, item);
  form.value.widgets = widgets;
};

const onMetricSourceChange = widget => {
  if (widget.source === 'aggregation') {
    widget.aggregation_op = widget.aggregation_op || 'count';
    widget.aggregation_entity = widget.aggregation_entity || 'conversations';
    widget.aggregation_field = widget.aggregation_field || '';
    widget.aggregation_group_field = widget.aggregation_group_field || '';
  } else {
    widget.metric = widget.metric || 'conversations_count';
  }
};

const aggregationFieldOptions = widget => {
  const entity = widget.aggregation_entity || 'conversations';
  const attrs =
    entity === 'contacts'
      ? contactAttributes.value || []
      : conversationAttributes.value || [];
  const op = widget.aggregation_op || 'count';
  // Count can target any attribute (non-empty presence). Sum/avg/min/max need numeric.
  const filtered =
    op === 'count'
      ? attrs
      : attrs.filter(attr =>
          SUMMABLE_CUSTOM_TYPES.has(normalizeAttrDisplayType(attr))
        );
  return filtered.map(attr => {
    const key = attr.attributeKey || attr.attribute_key;
    return {
      value: customAttributeColumnKey(key),
      label: attr.attributeDisplayName || attr.attribute_display_name || key,
    };
  });
};

const aggregationMeasureOptions = widget => {
  const options = aggregationFieldOptions(widget);
  if (widget.aggregation_op !== 'count') return options;
  return [
    { value: '', label: t('REPORT_PANELS.AGGREGATIONS.ALL_ROWS') },
    ...options,
  ];
};

const selectedMeasure = computed({
  get: () =>
    selectedWidget.value.source === 'aggregation'
      ? selectedWidget.value.aggregation_field
      : selectedWidget.value.metric,
  set: value => {
    if (selectedWidget.value.source === 'aggregation') {
      selectedWidget.value.aggregation_field = value;
    } else {
      selectedWidget.value.metric = value;
    }
  },
});
const selectedMeasureOptions = computed(() => {
  if (selectedWidget.value.source !== 'aggregation') return metricOptions.value;
  return aggregationMeasureOptions(selectedWidget.value);
});
const selectedOperation = computed(() => {
  const widget = selectedWidget.value;
  if (widget.source === 'aggregation') return widget.aggregation_op;
  return widget.metric.startsWith('avg_') || widget.metric === 'reply_time'
    ? 'avg'
    : 'count';
});

const onAggregationOpChange = widget => {
  const field = widget.aggregation_field;
  if (!field) return;
  const allowed = new Set(
    aggregationFieldOptions(widget).map(item => item.value)
  );
  if (!allowed.has(field)) {
    widget.aggregation_field = '';
  }
};

const DATE_GROUP_ATTR_TYPES = new Set(['date', 'datetime']);

const aggregationGroupFieldOptions = widget => {
  const entity = widget.aggregation_entity || 'conversations';
  const attrs =
    entity === 'contacts'
      ? contactAttributes.value || []
      : conversationAttributes.value || [];
  return attrs
    .filter(attr => DATE_GROUP_ATTR_TYPES.has(normalizeAttrDisplayType(attr)))
    .map(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      return {
        value: customAttributeColumnKey(key),
        label: attr.attributeDisplayName || attr.attribute_display_name || key,
      };
    });
};

const onTableKindChange = (widget, kind) => {
  const previousKind = widget.table_kind;
  const previousColumns = resolveTableColumns(previousKind, widget.columns);
  if (kind !== undefined && kind !== null && kind !== '') {
    widget.table_kind = kind;
  }
  if (
    SUMMARY_TABLE_KINDS.has(previousKind) &&
    SUMMARY_TABLE_KINDS.has(widget.table_kind)
  ) {
    widget.columns = resolveTableColumns(widget.table_kind, previousColumns);
    widget.column_aggregations = Object.fromEntries(
      Object.entries(widget.column_aggregations).filter(([column]) =>
        widget.columns.includes(column)
      )
    );
  } else {
    widget.columns = defaultColumnsForTableKind(widget.table_kind);
    widget.column_aggregations = {};
    widget.pivot = defaultPivotConfig();
  }
};

const buildPayload = () => {
  let filters = [];
  if (uiFilters.value.length) {
    const generated = filterQueryGenerator(
      uiFilters.value.map(filter => {
        const type = resolveFilterType(filter.attributeKey);
        const isContactCustom =
          type?.customAttributeType === 'contact_attribute';
        const isContactEntity = type?.customAttributeType === 'contact';
        const attributeKey =
          isContactCustom || isContactEntity
            ? type.sourceAttributeKey
            : filter.attributeKey.replace(
                new RegExp(`^${CONTACT_ATTR_PREFIX}|^${CONTACT_FILTER_PREFIX}`),
                ''
              );
        let customAttributeType = '';
        if (isContactCustom) customAttributeType = 'contact_attribute';
        else if (isContactEntity) customAttributeType = 'contact';
        return {
          attribute_key: attributeKey,
          filter_operator: filter.filterOperator,
          values: filter.values,
          query_operator: filter.queryOperator,
          custom_attribute_type: customAttributeType,
        };
      })
    );
    filters = generated.payload || [];
  }
  const widgets = form.value.widgets.map(widget => {
    const next = { ...ensureWidgetDefaults({ ...widget }) };
    if (next.type === 'table') {
      next.columns = resolveTableColumns(next.table_kind, next.columns);
      const aggregations = next.column_aggregations || {};
      next.column_aggregations = Object.fromEntries(
        Object.entries(aggregations).filter(
          ([key, op]) => next.columns.includes(key) && Boolean(op)
        )
      );
      if (
        SUMMARY_TABLE_KINDS.has(next.table_kind) &&
        next.pivot?.column_attribute
      ) {
        next.pivot = {
          column_attribute: next.pivot.column_attribute,
          column_values: Array.isArray(next.pivot.column_values)
            ? next.pivot.column_values.slice(0, MAX_PIVOT_VALUES)
            : [],
          show_row_totals: next.pivot.show_row_totals !== false,
        };
      } else {
        next.pivot = defaultPivotConfig();
      }
    }
    return next;
  });
  return {
    saved_report_panel: {
      ...form.value,
      widgets,
      filters,
    },
  };
};

const configurationValid = computed(
  () =>
    form.value.widgets.length > 0 &&
    form.value.widgets.every(
      widget =>
        widget.source !== 'aggregation' ||
        widget.aggregation_op === 'count' ||
        Boolean(widget.aggregation_field)
    ) &&
    uiFilters.value.every(
      filter =>
        !validateSingleFilter({
          attribute_key: filter.attributeKey,
          filter_operator: filter.filterOperator,
          values: filter.values,
        })
    ) &&
    (!isCustomRange.value ||
      (form.value.custom_since &&
        form.value.custom_until &&
        form.value.custom_since <= form.value.custom_until))
);

const runPreview = async (payload, version) => {
  try {
    const response = await previewRequest.run(signal =>
      SavedReportPanelsAPI.preview(
        { ...payload, timezone_offset: -new Date().getTimezoneOffset() / 60 },
        { signal }
      )
    );
    if (!response || version !== previewVersion) return;
    preview.value = response.data;
    previewWidgets.value = payload.saved_report_panel.widgets;
  } catch {
    if (version === previewVersion) previewError.value = true;
  } finally {
    if (version === previewVersion) previewRunning.value = false;
  }
};

watch(
  () => [ready.value, configurationValid.value, JSON.stringify(buildPayload())],
  ([isReady, valid, payload], _previous, onCleanup) => {
    previewVersion += 1;
    const version = previewVersion;
    preview.value = null;
    previewError.value = false;
    previewRunning.value = isReady && valid;
    if (!isReady || !valid) return;
    const timer = setTimeout(
      () => runPreview(JSON.parse(payload), version),
      PREVIEW_DEBOUNCE_MS
    );
    onCleanup(() => {
      clearTimeout(timer);
      previewRequest.abort();
    });
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  previewVersion += 1;
});

const save = async () => {
  if (!form.value.name.trim()) {
    useAlert(t('REPORT_PANELS.ERRORS.NAME_REQUIRED'));
    return;
  }
  if (!form.value.widgets.length) {
    useAlert(t('REPORT_PANELS.ERRORS.WIDGET_REQUIRED'));
    return;
  }
  if (form.value.date_preset === 'custom') {
    syncCustomDates();
    if (!form.value.custom_since || !form.value.custom_until) {
      useAlert(t('REPORT_PANELS.ERRORS.CUSTOM_RANGE_REQUIRED'));
      return;
    }
  }
  if (uiFilters.value.length) {
    const rows = [].concat(conditionsRef.value || []);
    const valid =
      rows.length === uiFilters.value.length &&
      rows.every(row => row.validate());
    if (!valid) {
      useAlert(t('REPORT_PANELS.ERRORS.FILTERS_INVALID'));
      return;
    }
  }
  if (!configurationValid.value) {
    useAlert(t('REPORT_PANELS.EDITOR.INCOMPLETE'));
    return;
  }
  saving.value = true;
  try {
    const payload = buildPayload();
    if (props.isNew) {
      const { data } = await SavedReportPanelsAPI.create(payload);
      router.replace(accountScopedRoute('report_panels_show', { id: data.id }));
    } else {
      await SavedReportPanelsAPI.update(route.params.id, payload);
      router.push(
        accountScopedRoute('report_panels_show', { id: route.params.id })
      );
    }
  } catch {
    useAlert(t('REPORT_PANELS.ERRORS.SAVE'));
  } finally {
    saving.value = false;
  }
};

const destroyPanel = async () => {
  if (props.isNew) return;
  try {
    await SavedReportPanelsAPI.delete(route.params.id);
    router.push(accountScopedRoute('report_panels_index'));
  } catch {
    useAlert(t('REPORT_PANELS.ERRORS.SAVE'));
  }
};

const cancelEdit = () => {
  if (props.isNew) {
    router.push(accountScopedRoute('report_panels_index'));
    return;
  }
  router.push(
    accountScopedRoute('report_panels_show', { id: route.params.id })
  );
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('attributes/get'),
      store.dispatch('agents/get'),
      store.dispatch('inboxes/get'),
      store.dispatch('teams/get'),
      store.dispatch('labels/get'),
      store.dispatch('campaigns/get'),
    ]);
    await loadExisting();
    ready.value = !loadFailed.value;
  } catch {
    loadFailed.value = true;
    useAlert(t('REPORT_PANELS.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <ReportHeader :header-title="pageTitle">
    <div class="flex gap-2">
      <Button
        :label="t('REPORT_PANELS.BACK')"
        variant="ghost"
        size="sm"
        @click="cancelEdit"
      />
      <Button
        v-if="!isNew"
        :label="t('REPORT_PANELS.DELETE')"
        color="ruby"
        variant="ghost"
        size="sm"
        @click="destroyPanel"
      />
      <Button
        :label="t('REPORT_PANELS.SAVE')"
        size="sm"
        :is-loading="saving"
        :disabled="!ready"
        data-testid="save-panel"
        @click="save"
      />
    </div>
  </ReportHeader>
  <div class="w-full min-w-0 max-w-7xl mx-auto flex flex-col gap-5 pb-8">
    <Spinner v-if="loading" class="self-center" />
    <p v-else-if="loadFailed" role="alert" class="text-sm text-n-ruby-11">
      {{ t('REPORT_PANELS.ERRORS.LOAD') }}
    </p>
    <template v-else>
      <nav
        :aria-label="t('REPORT_PANELS.EDITOR.STEPS_LABEL')"
        class="grid grid-cols-2 md:grid-cols-4 gap-2"
      >
        <Button
          v-for="(item, index) in EDITOR_STEPS"
          :key="item"
          :label="`${index + 1}. ${t(`REPORT_PANELS.EDITOR.STEPS.${item}`)}`"
          :variant="step === index ? 'faded' : 'ghost'"
          :color="step === index ? 'blue' : 'slate'"
          :aria-current="step === index ? 'step' : undefined"
          class="!h-auto !text-start justify-start min-w-0 [&_span]:!whitespace-normal [&_span]:!overflow-visible [&_span]:!text-clip"
          :data-testid="`step-${index}`"
          @click="step = index"
        />
      </nav>
      <div class="grid grid-cols-1 xl:grid-cols-2 gap-6 min-w-0 items-start">
        <div class="min-w-0 flex flex-col gap-5">
          <div v-show="step < 3" class="flex items-end gap-2 min-w-0">
            <div class="flex-1 min-w-0 grid gap-1.5">
              <span class="text-sm font-medium text-n-slate-12">{{
                t('REPORT_PANELS.EDITOR.CONTENT')
              }}</span>
              <ComboBox
                v-model="selectedId"
                :options="widgetOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.EDITOR.CONTENT')"
                teleport
                data-testid="content-picker"
              />
            </div>
            <Button
              v-tooltip="t('REPORT_PANELS.EDITOR.ADD')"
              icon="i-lucide-plus"
              variant="faded"
              :aria-label="t('REPORT_PANELS.EDITOR.ADD')"
              :disabled="form.widgets.length >= 12"
              data-testid="add-content"
              @click="addWidget('metric')"
            />
          </div>
          <section
            v-show="step === 0"
            class="grid gap-4"
            data-testid="choose-step"
          >
            <Input
              v-model="form.name"
              :label="t('REPORT_PANELS.FIELDS.NAME')"
              :placeholder="t('REPORT_PANELS.FIELDS.NAME_PLACEHOLDER')"
              data-testid="panel-name"
            />
            <TextArea
              v-model="form.description"
              :label="t('REPORT_PANELS.FIELDS.DESCRIPTION')"
              auto-height
              min-height="3rem"
            />
            <template v-if="selectedWidget">
              <div
                class="grid grid-cols-3 gap-2"
                role="group"
                :aria-label="t('REPORT_PANELS.EDITOR.TYPE')"
              >
                <button
                  v-for="type in PANEL_TYPES"
                  :key="type.value"
                  type="button"
                  class="flex flex-col items-center justify-center gap-2 rounded-xl p-4 min-w-0 text-sm text-n-slate-12 focus-visible:ring-2 focus-visible:ring-n-blue-9"
                  :class="
                    selectedWidget.type === type.value
                      ? 'bg-n-blue-3 ring-1 ring-n-blue-8'
                      : 'bg-n-alpha-1 hover:bg-n-alpha-2'
                  "
                  :aria-pressed="selectedWidget.type === type.value"
                  :data-testid="`type-${type.value}`"
                  @click="changeWidgetType(type.value)"
                >
                  <Icon :icon="type.icon" class="size-5" />
                  {{
                    t(`REPORT_PANELS.EDITOR.TYPES.${type.value.toUpperCase()}`)
                  }}
                </button>
              </div>
              <Input
                v-model="selectedWidget.title"
                :label="t('REPORT_PANELS.EDITOR.TITLE')"
              />
              <template v-if="selectedWidget.type !== 'table'">
                <div class="grid gap-1.5 text-sm text-n-slate-12">
                  <span>{{ t('REPORT_PANELS.FIELDS.METRIC_SOURCE') }}</span>
                  <ComboBox
                    v-model="selectedWidget.source"
                    :options="metricSourceOptions"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.FIELDS.METRIC_SOURCE')"
                    teleport
                    @update:model-value="onMetricSourceChange(selectedWidget)"
                  />
                </div>
                <div
                  v-if="selectedWidget.source === 'preset'"
                  class="grid gap-1.5 text-sm text-n-slate-12"
                >
                  <span>{{ t('REPORT_PANELS.EDITOR.MEASURE') }}</span>
                  <ComboBox
                    v-model="selectedWidget.metric"
                    :options="metricOptions"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.EDITOR.MEASURE')"
                    teleport
                    data-testid="metric-picker"
                  />
                </div>
                <template v-else>
                  <div class="grid gap-1.5 text-sm text-n-slate-12">
                    <span>{{
                      t('REPORT_PANELS.FIELDS.AGGREGATION_ENTITY')
                    }}</span>
                    <ComboBox
                      v-model="selectedWidget.aggregation_entity"
                      :options="aggregationEntityOptions"
                      :allow-deselect="false"
                      :aria-label="t('REPORT_PANELS.FIELDS.AGGREGATION_ENTITY')"
                      teleport
                      @update:model-value="
                        selectedWidget.aggregation_field = '';
                        selectedWidget.aggregation_group_field = '';
                      "
                    />
                  </div>
                  <div class="grid gap-1.5 text-sm text-n-slate-12">
                    <span>{{ t('REPORT_PANELS.EDITOR.MEASURE') }}</span>
                    <ComboBox
                      v-model="selectedWidget.aggregation_field"
                      :options="aggregationMeasureOptions(selectedWidget)"
                      :allow-deselect="false"
                      :aria-label="t('REPORT_PANELS.EDITOR.MEASURE')"
                      teleport
                    />
                  </div>
                </template>
              </template>
              <PanelTablePivotBuilder
                v-else
                :key="selectedWidget.id"
                :widget="selectedWidget"
                :table-kind-options="tableKindOptions"
                :conversation-attributes="conversationAttributes"
                :contact-attributes="contactAttributes"
                :show-grouping="false"
                :show-operations="false"
                @table-kind-change="
                  kind => onTableKindChange(selectedWidget, kind)
                "
              />
            </template>
          </section>
          <section
            v-show="step === 1"
            class="grid gap-4"
            data-testid="group-step"
          >
            <template v-if="selectedWidget">
              <PanelTablePivotBuilder
                v-if="selectedWidget.type === 'table'"
                :key="selectedWidget.id"
                :widget="selectedWidget"
                :table-kind-options="tableKindOptions"
                :conversation-attributes="conversationAttributes"
                :contact-attributes="contactAttributes"
                @table-kind-change="
                  kind => onTableKindChange(selectedWidget, kind)
                "
              />
              <template v-else>
                <div class="grid gap-1.5 text-sm text-n-slate-12">
                  <div class="flex items-center gap-1">
                    <span>{{ t('REPORT_PANELS.EDITOR.MEASURE') }}</span>
                    <Button
                      v-tooltip="t('REPORT_PANELS.EDITOR.BREAKDOWN_HINT')"
                      icon="i-lucide-info"
                      variant="ghost"
                      color="slate"
                      size="xs"
                      :aria-label="t('REPORT_PANELS.EDITOR.BREAKDOWN_HINT')"
                    />
                  </div>
                  <ComboBox
                    v-model="selectedMeasure"
                    :options="selectedMeasureOptions"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.EDITOR.MEASURE')"
                    teleport
                    data-testid="group-measure"
                  />
                </div>
                <div class="grid gap-1.5 text-sm text-n-slate-12">
                  <div class="flex items-center gap-1">
                    <span>{{ t('REPORT_PANELS.EDITOR.OPERATION') }}</span>
                    <Button
                      v-if="selectedWidget.source !== 'aggregation'"
                      v-tooltip="t('REPORT_PANELS.EDITOR.OPERATION_HINT')"
                      icon="i-lucide-info"
                      variant="ghost"
                      color="slate"
                      size="xs"
                      :aria-label="t('REPORT_PANELS.EDITOR.OPERATION_HINT')"
                    />
                  </div>
                  <ComboBox
                    :model-value="selectedOperation"
                    :options="aggregationOpOptions"
                    :disabled="selectedWidget.source !== 'aggregation'"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.EDITOR.OPERATION')"
                    teleport
                    @update:model-value="
                      selectedWidget.aggregation_op = $event;
                      onAggregationOpChange(selectedWidget);
                    "
                  />
                </div>
                <div
                  v-if="selectedWidget.type === 'chart'"
                  class="grid gap-1.5 text-sm text-n-slate-12"
                >
                  <span>{{ t('REPORT_PANELS.EDITOR.GROUP_BY') }}</span>
                  <ComboBox
                    v-model="selectedWidget.group_by"
                    :options="groupOptions"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.EDITOR.GROUP_BY')"
                    teleport
                    data-testid="chart-group"
                  />
                </div>
                <div
                  v-if="
                    selectedWidget.source === 'aggregation' &&
                    aggregationGroupFieldOptions(selectedWidget).length
                  "
                  class="grid gap-1.5 text-sm text-n-slate-12"
                >
                  <span>{{ t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE') }}</span>
                  <ComboBox
                    v-model="selectedWidget.aggregation_group_field"
                    :options="[
                      {
                        value: '',
                        label: t(
                          'REPORT_PANELS.AGGREGATIONS.GROUP_BY_CREATED_AT'
                        ),
                      },
                      ...aggregationGroupFieldOptions(selectedWidget),
                    ]"
                    :allow-deselect="false"
                    :aria-label="t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE')"
                    teleport
                  />
                </div>
              </template>
              <div class="flex gap-1">
                <Button
                  v-tooltip="t('REPORT_PANELS.WIDGETS.MOVE_UP')"
                  icon="i-lucide-arrow-up"
                  variant="ghost"
                  color="slate"
                  :aria-label="t('REPORT_PANELS.WIDGETS.MOVE_UP')"
                  :disabled="selectedIndex === 0"
                  @click="moveWidget(selectedIndex, -1)"
                />
                <Button
                  v-tooltip="t('REPORT_PANELS.WIDGETS.MOVE_DOWN')"
                  icon="i-lucide-arrow-down"
                  variant="ghost"
                  color="slate"
                  :aria-label="t('REPORT_PANELS.WIDGETS.MOVE_DOWN')"
                  :disabled="selectedIndex === form.widgets.length - 1"
                  @click="moveWidget(selectedIndex, 1)"
                />
                <Button
                  v-tooltip="t('REPORT_PANELS.WIDGETS.REMOVE')"
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  :aria-label="t('REPORT_PANELS.WIDGETS.REMOVE')"
                  :disabled="form.widgets.length === 1"
                  @click="removeWidget(selectedIndex)"
                />
              </div>
            </template>
          </section>
          <section
            v-show="step === 2"
            class="grid gap-4 min-w-0"
            data-testid="filters-step"
          >
            <div class="grid gap-1.5 text-sm text-n-slate-12">
              <span>{{ t('REPORT_PANELS.FIELDS.DATE_PRESET') }}</span>
              <ComboBox
                v-model="form.date_preset"
                :options="datePresetOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.FIELDS.DATE_PRESET')"
                teleport
                data-testid="date-preset"
                @update:model-value="onPresetChange"
              />
            </div>
            <div class="grid gap-1.5 text-sm text-n-slate-12">
              <div class="flex items-center gap-1">
                <span>{{ t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE') }}</span>
                <Button
                  v-tooltip="t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE_HINT')"
                  icon="i-lucide-info"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  :aria-label="t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE_HINT')"
                />
              </div>
              <ComboBox
                v-model="form.date_attribute"
                :options="dateAttributeOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.FIELDS.DATE_ATTRIBUTE')"
                teleport
              />
            </div>
            <div
              v-if="isCustomRange"
              class="grid grid-cols-1 sm:grid-cols-2 gap-3 min-w-0"
            >
              <Input
                v-for="(date, index) in customDateValues"
                :key="index"
                :model-value="date"
                type="date"
                :label="
                  t(
                    index === 0
                      ? 'REPORT_PANELS.EDITOR.START_DATE'
                      : 'REPORT_PANELS.EDITOR.END_DATE'
                  )
                "
                :data-testid="`custom-date-${index}`"
                @update:model-value="value => onCustomDateChange(index, value)"
              />
            </div>
            <div class="flex items-center gap-2 text-sm text-n-slate-12">
              <Switch
                v-model="form.business_hours"
                :aria-label="t('REPORT_PANELS.FIELDS.BUSINESS_HOURS')"
              />
              {{ t('REPORT_PANELS.FIELDS.BUSINESS_HOURS') }}
            </div>
            <div class="flex items-center gap-2 min-w-0">
              <h2 class="text-sm font-medium text-n-slate-12 flex-1">
                {{ t('REPORT_PANELS.FILTERS.TITLE') }}
              </h2>
              <Button
                v-tooltip="
                  t(
                    hasMixedFilterGroups
                      ? 'REPORT_PANELS.FILTERS.MIXED_GROUPS_BANNER'
                      : 'REPORT_PANELS.FILTERS.HINT'
                  )
                "
                icon="i-lucide-info"
                variant="ghost"
                color="slate"
                :aria-label="t('REPORT_PANELS.FILTERS.HINT')"
              />
              <Button
                v-tooltip="t('REPORT_PANELS.FILTERS.ADD')"
                icon="i-lucide-plus"
                variant="faded"
                :aria-label="t('REPORT_PANELS.FILTERS.ADD')"
                :disabled="uiFilters.length >= 10"
                data-testid="add-filter"
                @click="addFilter"
              />
            </div>
            <ul
              class="grid gap-3 min-w-0 [&_button]:max-w-full [&_input]:max-w-full"
            >
              <template v-for="(filter, index) in uiFilters" :key="index">
                <ConditionRow
                  v-if="index === 0"
                  ref="conditionsRef"
                  v-model:attribute-key="filter.attributeKey"
                  v-model:filter-operator="filter.filterOperator"
                  v-model:values="filter.values"
                  :filter-types="panelFilterTypes"
                  :show-query-operator="false"
                  @remove="removeFilter(index)"
                />
                <ConditionRow
                  v-else
                  ref="conditionsRef"
                  v-model:attribute-key="filter.attributeKey"
                  v-model:filter-operator="filter.filterOperator"
                  v-model:values="filter.values"
                  v-model:query-operator="uiFilters[index - 1].queryOperator"
                  :filter-types="panelFilterTypes"
                  show-query-operator
                  @remove="removeFilter(index)"
                />
              </template>
            </ul>
          </section>
          <section
            v-show="step === 3"
            class="grid gap-4"
            data-testid="preview-step"
          >
            <Input
              v-model="form.name"
              :label="t('REPORT_PANELS.FIELDS.NAME')"
              :placeholder="t('REPORT_PANELS.FIELDS.NAME_PLACEHOLDER')"
            />
            <div class="flex items-center gap-2 text-sm text-n-slate-12">
              <Switch
                v-model="form.favorite"
                :aria-label="t('REPORT_PANELS.FIELDS.FAVORITE')"
              />
              {{ t('REPORT_PANELS.FIELDS.FAVORITE') }}
            </div>
          </section>
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="step > 0"
              :label="t('REPORT_PANELS.EDITOR.PREVIOUS')"
              variant="ghost"
              color="slate"
              data-testid="previous-step"
              @click="step -= 1"
            />
            <Button
              v-if="step < 3"
              :label="t('REPORT_PANELS.EDITOR.NEXT')"
              data-testid="next-step"
              @click="step += 1"
            />
          </div>
        </div>
        <aside
          class="min-w-0 w-full rounded-xl bg-n-alpha-1 p-4 grid gap-4"
          :aria-label="t('REPORT_PANELS.EDITOR.STEPS.PREVIEW')"
          :aria-busy="previewRunning"
          data-testid="live-preview"
        >
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-medium text-n-slate-12 flex-1">
              {{ t('REPORT_PANELS.EDITOR.STEPS.PREVIEW') }}
            </h2>
            <Button
              v-tooltip="t('REPORT_PANELS.EDITOR.PREVIEW_HINT')"
              icon="i-lucide-info"
              variant="ghost"
              color="slate"
              size="xs"
              :aria-label="t('REPORT_PANELS.EDITOR.PREVIEW_HINT')"
            />
          </div>
          <div role="status" aria-live="polite" class="text-sm text-n-slate-11">
            <div v-if="previewRunning" class="flex items-center gap-2">
              <Spinner />
              <span>{{ t('REPORT_PANELS.EDITOR.LOADING') }}</span>
            </div>
            <span v-else-if="previewError" class="text-n-ruby-11">{{
              t('REPORT_PANELS.EDITOR.PREVIEW_ERROR')
            }}</span>
            <span v-else-if="!preview">{{
              t('REPORT_PANELS.EDITOR.INCOMPLETE')
            }}</span>
          </div>
          <template v-if="preview">
            <PanelWidgetCard
              v-for="widget in previewWidgets"
              :key="widget.id"
              :widget="widget"
              :result="resultById[widget.id]"
              :attribute-labels="attributeLabels"
              :attribute-types="attributeTypes"
              class="min-w-0 max-w-full"
            />
          </template>
        </aside>
      </div>
    </template>
  </div>
</template>
