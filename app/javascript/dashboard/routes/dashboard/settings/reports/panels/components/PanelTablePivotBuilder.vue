<script setup>
/* eslint-disable vue/no-mutating-props -- widget is the mutable draft owned by Edit.vue */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  SUMMARY_TABLE_KINDS,
  PIVOT_COLUMN_ATTR_TYPES,
  MAX_PIVOT_VALUES,
  TABLE_COLUMN_OPTIONS,
  AGGREGATION_OPS,
  SUMMABLE_SYSTEM_COLUMNS,
  defaultColumnsForTableKind,
  customAttributeColumnKey,
  customAttributeMeasureColumnKey,
  parseCustomAttributeColumn,
  summaryMeasureOpsForAttrType,
  summaryIdentityColumnsFor,
  summarySystemMeasureKeysFor,
  normalizeAttrDisplayType,
  isCustomAttributeColumn,
} from '../panelConstants';

const props = defineProps({
  widget: { type: Object, required: true },
  tableKindOptions: { type: Array, default: () => [] },
  conversationAttributes: { type: Array, default: () => [] },
  contactAttributes: { type: Array, default: () => [] },
  showGrouping: { type: Boolean, default: true },
  showOperations: { type: Boolean, default: true },
});
const emit = defineEmits(['tableKindChange']);
const { t } = useI18n();
const addField = ref('');
const addOp = ref('count');
const isSummary = computed(() =>
  SUMMARY_TABLE_KINDS.has(props.widget.table_kind)
);
const selectedColumns = computed(() =>
  props.widget.columns?.length
    ? props.widget.columns
    : defaultColumnsForTableKind(props.widget.table_kind)
);
const systemOp = key =>
  key.startsWith('avg_') || ['csat_avg', 'share_percent'].includes(key)
    ? 'avg'
    : 'count';
const fields = computed(() => {
  const system = summarySystemMeasureKeysFor(props.widget.table_kind).map(
    key => ({
      value: key,
      label: t(`REPORT_PANELS.COLUMNS.${key}`),
      ops: [systemOp(key)],
    })
  );
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
        ops: summaryMeasureOpsForAttrType(type),
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
const columnFor = (field, op, parsed = {}) =>
  field.key
    ? customAttributeMeasureColumnKey(field.key, op, {
        ...parsed,
        contact: field.contact,
      })
    : field.value;
const measures = computed(() =>
  selectedColumns.value
    .filter(
      key => !summaryIdentityColumnsFor(props.widget.table_kind).includes(key)
    )
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
        parsed,
        label:
          field?.label ||
          parsed.attrKey ||
          t(`REPORT_PANELS.COLUMNS.${column}`),
        op: parsed.op || (parsed.attrKey ? 'count' : systemOp(column)),
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
    ...summaryIdentityColumnsFor(props.widget.table_kind),
    ...columns,
  ];
};
const canShowFooter = column =>
  isCustomAttributeColumn(column) || SUMMABLE_SYSTEM_COLUMNS.has(column);
const replaceMeasure = (row, fieldId, op) => {
  const field = fieldById.value[fieldId];
  if (!field) return;
  const nextColumn = columnFor(
    field,
    op,
    fieldId === row.fieldId ? row.parsed : {}
  );
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
};
const removeMeasure = column => {
  writeMeasures(
    measures.value.filter(row => row.column !== column).map(row => row.column)
  );
  const totals = { ...props.widget.column_aggregations };
  delete totals[column];
  props.widget.column_aggregations = totals;
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
const setSplit = value => {
  props.widget.pivot.column_attribute = value;
  props.widget.pivot.column_values = [];
};
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
</script>

<template>
  <div class="min-w-0 grid gap-4">
    <div
      v-if="showGrouping || !isSummary"
      class="grid gap-1.5 text-sm text-n-slate-12"
    >
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
    <template v-if="isSummary">
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
