<script setup>
/* eslint-disable vue/no-mutating-props -- widget is the mutable draft owned by Edit.vue */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  ROW_GRANULARITIES,
  TOP_N_LIMITS,
  MEASURE_DISPLAYS,
  COLUMN_FORMAT_TYPES,
  COLUMN_DECIMALS,
  PIVOT_SYSTEM_MEASURES,
  PIVOT_IDENTITY_COLUMNS,
  isAdditiveMeasure,
  cleanTableOptions,
  pivotColumnKey,
  isContactCustomAttributeColumn,
  PIVOT_COLUMN_ATTR_TYPES,
  MAX_PIVOT_VALUES,
  TABLE_COLUMN_OPTIONS,
  AGGREGATION_OPS,
  defaultColumnsForTableKind,
  customAttributeColumnKey,
  customAttributeMeasureColumnKey,
  parseCustomAttributeColumn,
  measureOpsForAttrType,
  normalizeAttrDisplayType,
  isCustomAttributeColumn,
} from '../panelConstants';

const props = defineProps({
  widget: { type: Object, required: true },
  tableKindOptions: { type: Array, default: () => [] },
  conversationAttributes: { type: Array, default: () => [] },
  contactAttributes: { type: Array, default: () => [] },
  previewPivot: { type: Object, default: null },
  showGrouping: { type: Boolean, default: true },
  showOperations: { type: Boolean, default: true },
});
const emit = defineEmits(['tableKindChange']);
const { t } = useI18n();
const addField = ref('');
const addOp = ref('count');
const isPivot = computed(() => props.widget.table_kind === 'pivot');
const selectedColumns = computed(() =>
  props.widget.columns?.length
    ? props.widget.columns
    : defaultColumnsForTableKind(props.widget.table_kind)
);
const fields = computed(() => {
  const system = [...PIVOT_SYSTEM_MEASURES].map(key => ({
    value: key,
    label: t(`REPORT_PANELS.COLUMNS.${key}`),
    ops: ['count'],
  }));
  const custom = (attrs, contact) =>
    attrs.map(attr => {
      const key = attr.attributeKey || attr.attribute_key;
      const name =
        attr.attributeDisplayName || attr.attribute_display_name || key;
      const type = normalizeAttrDisplayType(attr);
      return {
        value: `${contact ? 'contact_ca:' : 'ca:'}${key}`,
        label: contact
          ? t('REPORT_PANELS.COLUMNS.CONTACT_CA_PREFIX', { name })
          : name,
        key,
        contact,
        ops: measureOpsForAttrType(type),
        canSplit: !contact && PIVOT_COLUMN_ATTR_TYPES.has(type),
        values: attr.attributeValues || attr.attribute_values || [],
      };
    });
  return [
    ...system,
    ...custom(props.conversationAttributes, false),
    ...custom(props.contactAttributes, true),
  ];
});
const fieldById = computed(() =>
  Object.fromEntries(fields.value.map(field => [field.value, field]))
);
const fieldOptions = computed(() =>
  fields.value.map(({ value, label }) => ({ value, label }))
);
const opOptions = ops =>
  AGGREGATION_OPS.filter(item => ops.includes(item.value)).map(item => ({
    value: item.value,
    label: t(item.labelKey),
  }));
const columnFor = (field, op) =>
  field.key
    ? customAttributeMeasureColumnKey(field.key, op, { contact: field.contact })
    : field.value;
const measures = computed(() =>
  selectedColumns.value
    .filter(key => !PIVOT_IDENTITY_COLUMNS.has(key))
    .map(column => {
      const parsed = parseCustomAttributeColumn(column);
      const fieldId = parsed.attrKey
        ? `${parsed.contact ? 'contact_ca:' : 'ca:'}${parsed.attrKey}`
        : column;
      const field = fieldById.value[fieldId];
      return {
        column,
        fieldId,
        field,
        label:
          field?.label ||
          parsed.attrKey ||
          t(`REPORT_PANELS.COLUMNS.${column}`),
        op: parsed.op || 'count',
        ops: field?.ops || [parsed.op || 'count'],
      };
    })
);
const addOps = computed(
  () => fieldById.value[addField.value]?.ops || ['count']
);
const selectAddField = value => {
  addField.value = value;
  const ops = fieldById.value[value]?.ops || ['count'];
  addOp.value = ops.includes('sum') ? 'sum' : ops[0];
};
const writeMeasures = columns => {
  props.widget.columns = [
    ...selectedColumns.value.filter(key => PIVOT_IDENTITY_COLUMNS.has(key)),
    ...columns,
  ];
};
const canShowFooter = column =>
  isCustomAttributeColumn(column) || PIVOT_SYSTEM_MEASURES.has(column);
const replaceMeasure = (row, fieldId, op) => {
  const field = fieldById.value[fieldId];
  if (!field) return;
  const nextColumn = columnFor(field, op);
  if (nextColumn !== row.column && selectedColumns.value.includes(nextColumn))
    return;
  writeMeasures(
    measures.value.map(item =>
      item.column === row.column ? nextColumn : item.column
    )
  );
  const totals = { ...props.widget.column_aggregations };
  if (totals[row.column]) {
    if (canShowFooter(nextColumn)) totals[nextColumn] = totals[row.column];
    if (nextColumn !== row.column) delete totals[row.column];
  }
  props.widget.column_aggregations = totals;
  cleanTableOptions(props.widget, row.column, nextColumn);
};
const changeField = (row, fieldId) => {
  const field = fieldById.value[fieldId];
  if (!field) return;
  let op = field.ops.includes('sum') ? 'sum' : field.ops[0];
  if (field.ops.includes(row.op)) op = row.op;
  replaceMeasure(row, fieldId, op);
};
const addMeasure = () => {
  const field = fieldById.value[addField.value];
  if (!field) return;
  const column = columnFor(field, addOp.value);
  if (selectedColumns.value.includes(column)) return;
  writeMeasures([...measures.value.map(row => row.column), column]);
  addField.value = '';
  cleanTableOptions(props.widget);
};
const removeMeasure = column => {
  writeMeasures(
    measures.value.filter(row => row.column !== column).map(row => row.column)
  );
  const totals = { ...props.widget.column_aggregations };
  delete totals[column];
  props.widget.column_aggregations = totals;
  cleanTableOptions(props.widget);
};
const moveMeasure = (index, direction) => {
  const columns = measures.value.map(row => row.column);
  const [column] = columns.splice(index, 1);
  columns.splice(index + direction, 0, column);
  writeMeasures(columns);
};
const splitOptions = computed(() => [
  { value: '', label: t('REPORT_PANELS.EDITOR.NO_SPLIT') },
  ...fields.value
    .filter(field => field.canSplit)
    .map(({ value, label }) => ({ value, label })),
]);
const splitField = computed(
  () => fieldById.value[props.widget.pivot.column_attribute]
);
const splitValues = computed(() =>
  (splitField.value?.values || [])
    .filter(Boolean)
    .slice(0, MAX_PIVOT_VALUES)
    .map(value => ({ value, label: value }))
);
const detailOptions = computed(() => [
  ...(TABLE_COLUMN_OPTIONS[props.widget.table_kind] || []).map(value => ({
    value,
    label: t(`REPORT_PANELS.COLUMNS.${value}`),
  })),
  ...(props.widget.table_kind === 'contacts'
    ? props.contactAttributes
    : props.conversationAttributes
  ).map(attr => ({
    value: customAttributeColumnKey(attr.attributeKey || attr.attribute_key),
    label: attr.attributeDisplayName || attr.attribute_display_name,
  })),
]);
const setDetailColumns = columns => {
  // The runner interprets an empty selection as the default columns.
  props.widget.columns = columns.length
    ? columns
    : defaultColumnsForTableKind(props.widget.table_kind);
};
const footerOptions = computed(() => [
  { value: '', label: t('REPORT_PANELS.AGGREGATIONS.NONE') },
  ...opOptions(AGGREGATION_OPS.map(item => item.value)),
]);
const setFooter = (column, op) => {
  const totals = { ...props.widget.column_aggregations };
  if (op) totals[column] = op;
  else delete totals[column];
  props.widget.column_aggregations = totals;
};

const rowOptions = computed(() => [
  ...['agent', 'inbox', 'team', 'label', 'created_at'].map(value => ({
    value,
    label: t(`REPORT_PANELS.DYNAMIC.ROWS_${value.toUpperCase()}`),
  })),
  ...fields.value
    .filter(field => field.key)
    .map(({ value, label }) => ({ value, label })),
]);
const rowAttribute = computed(() => props.widget.pivot.row_attribute);
const setSplit = value => {
  props.widget.pivot.column_attribute = value;
  props.widget.pivot.column_values = [];
  cleanTableOptions(props.widget);
};
const setRow = value => {
  props.widget.pivot.row_attribute = value;
  if (value === 'created_at') props.widget.pivot.row_granularity ||= 'day';
  else delete props.widget.pivot.row_granularity;
  cleanTableOptions(props.widget);
};
const displayedPivotValues = computed(() => {
  if (!props.widget.pivot?.column_attribute) return [];
  if (props.widget.pivot.column_values?.length)
    return props.widget.pivot.column_values;
  if (
    props.previewPivot?.column_attribute === props.widget.pivot.column_attribute
  )
    return props.previewPivot.column_values || [];
  return splitValues.value.map(option => option.value);
});
const measureOptions = computed(() =>
  measures.value.flatMap(row => [
    { value: row.column, label: row.label },
    ...displayedPivotValues.value.map(value => ({
      value: pivotColumnKey(row.column, value),
      label: t('REPORT_PANELS.PIVOT.HEADER', {
        segment: value,
        measure: row.label,
      }),
    })),
  ])
);
const defaultSortColumn = computed(() =>
  rowAttribute.value === 'created_at'
    ? 'name'
    : measures.value.find(row => row.column === 'conversations_count')
        ?.column || measures.value[0]?.column
);
const controls = computed(() => [
  ...(rowAttribute.value === 'created_at'
    ? [
        {
          key: 'granularity',
          value: props.widget.pivot.row_granularity || 'day',
          options: ROW_GRANULARITIES.map(value => ({
            value,
            label: t(`REPORT_PANELS.EDITOR.GROUPS.${value.toUpperCase()}`),
          })),
        },
      ]
    : []),
  {
    key: 'sort_column',
    value: props.widget.sort?.column || defaultSortColumn.value,
    options: [
      { value: 'name', label: t('REPORT_PANELS.DYNAMIC.ROW_NAME') },
      ...measureOptions.value,
    ],
  },
  {
    key: 'sort_direction',
    value:
      props.widget.sort?.direction ||
      (rowAttribute.value === 'created_at' ? 'asc' : 'desc'),
    options: ['asc', 'desc'].map(value => ({
      value,
      label: t(`REPORT_PANELS.DYNAMIC.${value.toUpperCase()}`),
    })),
  },
  {
    key: 'top_limit',
    value: props.widget.top_n?.limit ?? '',
    options: TOP_N_LIMITS.map(value => ({
      value: value ?? '',
      label: value == null ? t('REPORT_PANELS.DYNAMIC.ALL') : String(value),
    })),
  },
  ...(props.widget.top_n?.limit
    ? [
        {
          key: 'top_column',
          value: props.widget.top_n.column,
          options: measureOptions.value,
        },
      ]
    : []),
]);
const setControl = (key, value) => {
  if (key === 'granularity') props.widget.pivot.row_granularity = value;
  if (key.startsWith('sort_'))
    props.widget.sort = {
      column: props.widget.sort?.column || defaultSortColumn.value,
      direction:
        props.widget.sort?.direction ||
        (rowAttribute.value === 'created_at' ? 'asc' : 'desc'),
      [key === 'sort_column' ? 'column' : 'direction']: value,
    };
  if (key.startsWith('top_')) {
    props.widget.top_n = {
      limit: props.widget.top_n?.limit ?? null,
      column: props.widget.top_n?.column || measures.value[0]?.column,
      include_others: props.widget.top_n?.include_others || false,
      [key === 'top_limit' ? 'limit' : 'column']: value === '' ? null : value,
    };
    cleanTableOptions(props.widget);
  }
};
const hasContactMeasures = computed(() =>
  measures.value.some(row => isContactCustomAttributeColumn(row.column))
);
const setOthers = value => {
  props.widget.top_n.include_others = value;
};
const displayOptions = row =>
  MEASURE_DISPLAYS.filter(
    value => value === 'value' || isAdditiveMeasure(row.column)
  ).map(value => ({
    value,
    label: t(`REPORT_PANELS.DYNAMIC.DISPLAY_${value.toUpperCase()}`),
  }));
const setDisplay = (column, value) => {
  const displays = { ...props.widget.measure_display };
  if (value === 'value') delete displays[column];
  else displays[column] = value;
  props.widget.measure_display = displays;
  cleanTableOptions(props.widget);
};
const formatOptions = computed(() =>
  COLUMN_FORMAT_TYPES.map(value => ({
    value,
    label: t(
      `REPORT_PANELS.DYNAMIC.FORMAT_${value ? value.toUpperCase() : 'AUTO'}`
    ),
  }))
);
const decimalsOptions = COLUMN_DECIMALS.map(value => ({
  value,
  label: String(value),
}));
const setFormat = (column, key, value) => {
  const formats = { ...props.widget.column_formats };
  if (key === 'type' && !value) delete formats[column];
  else formats[column] = { type: 'integer', ...formats[column], [key]: value };
  props.widget.column_formats = formats;
};
</script>

<template>
  <div class="min-w-0 grid gap-4">
    <div v-if="!isPivot" class="grid gap-1.5 text-sm text-n-slate-12">
      <span>{{ t('REPORT_PANELS.EDITOR.GROUP_BY') }}</span>
      <ComboBox
        :model-value="widget.table_kind"
        :options="tableKindOptions"
        :allow-deselect="false"
        :aria-label="t('REPORT_PANELS.EDITOR.GROUP_BY')"
        teleport
        data-testid="table-group"
        @update:model-value="
          addField = '';
          emit('tableKindChange', $event);
        "
      />
    </div>
    <template v-if="isPivot">
      <div v-if="showGrouping" class="grid gap-3 sm:grid-cols-2">
        <div class="grid gap-1.5 text-sm text-n-slate-12 min-w-0">
          <div class="flex items-center gap-1">
            <span>{{ t('REPORT_PANELS.DYNAMIC.ROWS') }}</span>
            <Button
              v-tooltip="t('REPORT_PANELS.DYNAMIC.ROWS_HINT')"
              icon="i-lucide-info"
              variant="ghost"
              color="slate"
              size="xs"
              :aria-label="t('REPORT_PANELS.DYNAMIC.ROWS_HINT')"
            />
          </div>
          <ComboBox
            :model-value="rowAttribute"
            :options="rowOptions"
            :allow-deselect="false"
            show-search
            :aria-label="t('REPORT_PANELS.DYNAMIC.ROWS')"
            teleport
            data-testid="pivot-rows"
            @update:model-value="setRow"
          />
        </div>
        <div
          v-for="control in controls"
          :key="control.key"
          class="grid gap-1.5 text-sm text-n-slate-12 min-w-0"
        >
          <span>{{
            t(`REPORT_PANELS.DYNAMIC.${control.key.toUpperCase()}`)
          }}</span>
          <ComboBox
            :model-value="control.value"
            :options="control.options"
            :allow-deselect="false"
            :aria-label="
              t(`REPORT_PANELS.DYNAMIC.${control.key.toUpperCase()}`)
            "
            teleport
            :data-testid="control.key"
            @update:model-value="setControl(control.key, $event)"
          />
        </div>
        <div
          v-if="widget.top_n?.limit"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <Switch
            :model-value="widget.top_n.include_others"
            :disabled="hasContactMeasures"
            :aria-label="t('REPORT_PANELS.DYNAMIC.OTHERS')"
            data-testid="include-others"
            @update:model-value="setOthers"
          />
          <span>{{ t('REPORT_PANELS.DYNAMIC.OTHERS') }}</span>
          <Button
            v-tooltip="t('REPORT_PANELS.DYNAMIC.OTHERS_HINT')"
            icon="i-lucide-info"
            variant="ghost"
            color="slate"
            size="xs"
            :aria-label="t('REPORT_PANELS.DYNAMIC.OTHERS_HINT')"
          />
        </div>
      </div>
      <div class="grid gap-3">
        <div
          v-for="(row, index) in measures"
          :key="row.column"
          class="rounded-xl bg-n-alpha-1 p-3 grid gap-2 min-w-0"
          data-testid="measure-row"
        >
          <div
            class="grid gap-3 min-w-0"
            :class="showOperations ? 'sm:grid-cols-2' : ''"
          >
            <div class="grid gap-1.5 text-sm text-n-slate-12 min-w-0">
              <span>{{ t('REPORT_PANELS.EDITOR.MEASURE') }}</span>
              <ComboBox
                :model-value="row.fieldId"
                :display-label="row.label"
                :options="fieldOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.EDITOR.MEASURE')"
                teleport
                data-testid="measure-field"
                @update:model-value="changeField(row, $event)"
              />
            </div>
            <div
              v-if="showOperations"
              class="grid gap-1.5 text-sm text-n-slate-12 min-w-0"
            >
              <span>{{ t('REPORT_PANELS.EDITOR.OPERATION') }}</span>
              <ComboBox
                :model-value="row.op"
                :options="opOptions(row.ops)"
                :disabled="!isCustomAttributeColumn(row.column)"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.EDITOR.OPERATION')"
                teleport
                data-testid="measure-operation"
                @update:model-value="replaceMeasure(row, row.fieldId, $event)"
              />
            </div>
          </div>
          <div v-if="showOperations" class="grid gap-3 sm:grid-cols-2">
            <div class="grid gap-1.5 text-sm text-n-slate-12 min-w-0">
              <div class="flex items-center gap-1">
                <span>{{ t('REPORT_PANELS.DYNAMIC.DISPLAY') }}</span>
                <Button
                  v-tooltip="t('REPORT_PANELS.DYNAMIC.PERCENT_HINT')"
                  icon="i-lucide-info"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :aria-label="t('REPORT_PANELS.DYNAMIC.PERCENT_HINT')"
                />
              </div>
              <ComboBox
                :model-value="widget.measure_display?.[row.column] || 'value'"
                :options="displayOptions(row)"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.DYNAMIC.DISPLAY')"
                teleport
                data-testid="measure-display"
                @update:model-value="setDisplay(row.column, $event)"
              />
            </div>
            <div class="grid gap-1.5 text-sm text-n-slate-12 min-w-0">
              <span>{{ t('REPORT_PANELS.DYNAMIC.FORMAT') }}</span>
              <ComboBox
                :model-value="widget.column_formats?.[row.column]?.type || ''"
                :options="formatOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.DYNAMIC.FORMAT')"
                teleport
                data-testid="measure-format"
                @update:model-value="setFormat(row.column, 'type', $event)"
              />
            </div>
            <div
              v-if="widget.column_formats?.[row.column]?.type === 'currency'"
              class="grid gap-1.5 text-sm text-n-slate-12 min-w-0"
            >
              <span>{{ t('REPORT_PANELS.DYNAMIC.SYMBOL') }}</span>
              <Input
                :model-value="
                  widget.column_formats[row.column].currency_symbol ?? '$'
                "
                :aria-label="t('REPORT_PANELS.DYNAMIC.SYMBOL')"
                data-testid="currency-symbol"
                @update:model-value="
                  setFormat(row.column, 'currency_symbol', $event)
                "
              />
            </div>
            <div
              v-if="widget.column_formats?.[row.column]"
              class="grid gap-1.5 text-sm text-n-slate-12 min-w-0"
            >
              <span>{{ t('REPORT_PANELS.DYNAMIC.DECIMALS') }}</span>
              <ComboBox
                :model-value="
                  widget.column_formats[row.column].decimals ??
                  (widget.column_formats[row.column].type === 'integer' ? 0 : 2)
                "
                :options="decimalsOptions"
                :allow-deselect="false"
                :aria-label="t('REPORT_PANELS.DYNAMIC.DECIMALS')"
                teleport
                data-testid="format-decimals"
                @update:model-value="setFormat(row.column, 'decimals', $event)"
              />
            </div>
          </div>
          <details
            v-if="showOperations && canShowFooter(row.column)"
            class="text-sm text-n-slate-11"
          >
            <summary class="cursor-pointer">
              {{ t('REPORT_PANELS.EDITOR.TOTALS') }}
            </summary>
            <ComboBox
              :model-value="widget.column_aggregations?.[row.column] || ''"
              :options="footerOptions"
              :allow-deselect="false"
              :aria-label="t('REPORT_PANELS.EDITOR.TOTALS')"
              class="mt-2"
              teleport
              @update:model-value="setFooter(row.column, $event)"
            />
          </details>
          <div class="flex gap-1">
            <Button
              v-tooltip="t('REPORT_PANELS.WIDGETS.MOVE_UP')"
              icon="i-lucide-arrow-up"
              size="sm"
              variant="ghost"
              color="slate"
              :aria-label="t('REPORT_PANELS.WIDGETS.MOVE_UP')"
              :disabled="index === 0"
              @click="moveMeasure(index, -1)"
            />
            <Button
              v-tooltip="t('REPORT_PANELS.WIDGETS.MOVE_DOWN')"
              icon="i-lucide-arrow-down"
              size="sm"
              variant="ghost"
              color="slate"
              :aria-label="t('REPORT_PANELS.WIDGETS.MOVE_DOWN')"
              :disabled="index === measures.length - 1"
              @click="moveMeasure(index, 1)"
            />
            <Button
              v-tooltip="t('REPORT_PANELS.PIVOT.REMOVE_MEASURE')"
              icon="i-lucide-trash-2"
              size="sm"
              variant="ghost"
              color="ruby"
              :aria-label="t('REPORT_PANELS.PIVOT.REMOVE_MEASURE')"
              :disabled="measures.length === 1"
              @click="removeMeasure(row.column)"
            />
          </div>
        </div>
      </div>
      <div class="grid gap-2 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">{{
          t('REPORT_PANELS.PIVOT.ADD_MEASURE')
        }}</span>
        <ComboBox
          :model-value="addField"
          :options="fieldOptions"
          :placeholder="t('REPORT_PANELS.PIVOT.ADD_MEASURE_PLACEHOLDER')"
          :allow-deselect="false"
          :aria-label="t('REPORT_PANELS.EDITOR.MEASURE')"
          teleport
          data-testid="add-measure-field"
          @update:model-value="selectAddField"
        />
        <div v-if="showOperations" class="grid gap-1.5 text-sm text-n-slate-12">
          <span>{{ t('REPORT_PANELS.EDITOR.OPERATION') }}</span>
          <ComboBox
            v-model="addOp"
            :options="opOptions(addOps)"
            :allow-deselect="false"
            :disabled="!addField"
            :aria-label="t('REPORT_PANELS.EDITOR.OPERATION')"
            teleport
            data-testid="add-measure-operation"
          />
        </div>
        <Button
          v-tooltip="t('REPORT_PANELS.PIVOT.ADD_MEASURE')"
          icon="i-lucide-plus"
          variant="faded"
          :aria-label="t('REPORT_PANELS.PIVOT.ADD_MEASURE')"
          :disabled="!addField"
          class="justify-self-start"
          data-testid="add-measure"
          @click="addMeasure"
        />
      </div>
      <template v-if="showGrouping">
        <div class="grid gap-1.5 text-sm text-n-slate-12">
          <div class="flex items-center gap-1">
            <span>{{ t('REPORT_PANELS.EDITOR.SPLIT') }}</span>
            <Button
              v-tooltip="t('REPORT_PANELS.EDITOR.SPLIT_HINT')"
              icon="i-lucide-info"
              variant="ghost"
              color="slate"
              size="xs"
              :aria-label="t('REPORT_PANELS.EDITOR.SPLIT_HINT')"
            />
          </div>
          <ComboBox
            :model-value="widget.pivot.column_attribute"
            :options="splitOptions"
            :allow-deselect="false"
            :aria-label="t('REPORT_PANELS.EDITOR.SPLIT')"
            teleport
            @update:model-value="setSplit"
          />
        </div>
        <div
          v-if="splitValues.length"
          class="grid gap-1.5 text-sm text-n-slate-12"
        >
          <span>{{ t('REPORT_PANELS.PIVOT.COLUMN_VALUES') }}</span>
          <ComboBox
            :model-value="widget.pivot.column_values"
            :options="splitValues"
            :placeholder="t('REPORT_PANELS.EDITOR.ALL_VALUES')"
            :aria-label="t('REPORT_PANELS.PIVOT.COLUMN_VALUES')"
            multiple
            teleport
            @update:model-value="widget.pivot.column_values = $event"
          />
        </div>
        <div
          v-if="widget.pivot.column_attribute"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <Switch
            v-model="widget.pivot.show_row_totals"
            :aria-label="t('REPORT_PANELS.PIVOT.SHOW_ROW_TOTALS')"
          />
          {{ t('REPORT_PANELS.PIVOT.SHOW_ROW_TOTALS') }}
        </div>
      </template>
    </template>
    <div v-else class="grid gap-1.5 text-sm text-n-slate-12">
      <span>{{ t('REPORT_PANELS.FIELDS.TABLE_COLUMNS') }}</span>
      <ComboBox
        :model-value="selectedColumns"
        :options="detailOptions"
        :aria-label="t('REPORT_PANELS.FIELDS.TABLE_COLUMNS')"
        multiple
        teleport
        data-testid="detail-columns"
        @update:model-value="setDetailColumns"
      />
    </div>
  </div>
</template>
