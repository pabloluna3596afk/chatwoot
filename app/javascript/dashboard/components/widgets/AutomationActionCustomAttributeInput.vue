<script>
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { useVariableCatalog } from 'dashboard/composables/useVariableCatalog';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InsertVariableButton from 'dashboard/components-next/variable/InsertVariableButton.vue';

const DAY_PRESETS = [7, 15, 30];
const MAX_RELATIVE_DAYS = 365;

export default {
  components: {
    ComboBox,
    VariablePicker,
    NextInput,
    NextButton,
    InsertVariableButton,
  },
  props: {
    modelValue: { type: [Object, Array], default: () => ({}) },
    attributeModel: {
      type: String,
      default: 'contact_attribute',
      validator: value =>
        ['contact_attribute', 'conversation_attribute'].includes(value),
    },
  },
  emits: ['update:modelValue'],
  setup() {
    const { variables } = useVariableCatalog('automation');
    return { catalogVariables: variables };
  },
  data() {
    return {
      // Switch away from native date/datetime inputs BEFORE writing Liquid,
      // otherwise the browser rejects `{{ ... }}` and emits '' (clears the action).
      preferLiquidMode: false,
      dayPresets: DAY_PRESETS,
    };
  },
  computed: {
    targetPath() {
      const scope = this.attributeModel.replace('_attribute', '');
      return this.selectedKey
        ? `${scope}.custom_attribute.${this.selectedKey}`
        : '';
    },
    attributeOptions() {
      const scope = this.attributeModel.replace('_attribute', '');
      return this.catalogVariables
        .filter(
          attribute =>
            attribute.available &&
            attribute.writable &&
            !attribute.managedBy &&
            attribute.writeContexts.includes('automation') &&
            attribute.reference.kind === 'custom_attribute' &&
            attribute.reference.scope === scope
        )
        .map(attribute => ({
          id: attribute.key,
          name: attribute.label,
          displayType: attribute.type,
          values: attribute.options,
        }));
    },
    selectedKey: {
      get() {
        return this.payload.attribute_key || '';
      },
      set(attributeKey) {
        this.preferLiquidMode = false;
        this.emitValue(attributeKey, '');
      },
    },
    selectedValue: {
      get() {
        const value = this.payload.value;
        return value === undefined || value === null ? '' : value;
      },
      set(value) {
        this.emitValue(this.selectedKey, value);
      },
    },
    payload() {
      const data = Array.isArray(this.modelValue)
        ? this.modelValue[0] || {}
        : this.modelValue || {};
      return data;
    },
    selectedAttribute() {
      return this.attributeOptions.find(item => item.id === this.selectedKey);
    },
    isDateAttribute() {
      return this.selectedAttribute?.displayType === 'date';
    },
    isDatetimeAttribute() {
      return this.selectedAttribute?.displayType === 'datetime';
    },
    isNumberAttribute() {
      return ['number', 'currency', 'percent'].includes(
        this.selectedAttribute?.displayType
      );
    },
    isListAttribute() {
      return this.selectedAttribute?.displayType === 'list';
    },
    isCheckboxAttribute() {
      return this.selectedAttribute?.displayType === 'checkbox';
    },
    valueUsesLiquid() {
      return (
        this.preferLiquidMode || String(this.selectedValue || '').includes('{{')
      );
    },
    relativeParsed() {
      return this.parseRelativeLiquid(this.selectedValue);
    },
    isRelativeLiquid() {
      return this.relativeParsed.base != null;
    },
    relativeDays() {
      return this.relativeParsed.days;
    },
    relativeBase() {
      if (this.isDatetimeAttribute) return 'now';
      return 'today';
    },
    relativeSummary() {
      const days = this.relativeDays;
      if (this.isDatetimeAttribute) {
        return days === 0
          ? this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATETIME_DYNAMIC_NOW')
          : this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_NOW_PLUS', {
              n: days,
            });
      }
      return days === 0
        ? this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_DYNAMIC_TODAY')
        : this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_TODAY_PLUS', {
            n: days,
          });
    },
    inputType() {
      // Fixed dates use the native picker (ISO YYYY-MM-DD only).
      // Relative dates use Liquid and leave the native picker.
      if (this.isDateAttribute && !this.valueUsesLiquid) return 'date';
      if (this.isDatetimeAttribute && !this.valueUsesLiquid) {
        return 'datetime-local';
      }
      if (this.isNumberAttribute && !this.valueUsesLiquid) return 'number';
      return 'text';
    },
    valuePlaceholder() {
      if (this.isNumberAttribute) {
        return this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_NUMBER_PLACEHOLDER');
      }
      return this.$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_VALUE_PLACEHOLDER');
    },
    showVariablePicker() {
      if (this.isDateAttribute) return false;
      return (
        this.selectedKey && !this.isListAttribute && !this.isCheckboxAttribute
      );
    },
  },
  watch: {
    modelValue: {
      immediate: true,
      handler() {
        if (String(this.payload.value || '').includes('{{')) {
          this.preferLiquidMode = true;
        }
      },
    },
  },
  methods: {
    selectTarget(binding) {
      this.selectedKey = this.catalogVariables.find(
        variable => variable.id === binding.id
      ).key;
    },
    emitValue(attributeKey, value) {
      let nextValue = value ?? '';
      if (
        this.isNumberAttribute &&
        nextValue !== '' &&
        !String(nextValue).includes('{{')
      ) {
        const asNumber = Number(nextValue);
        nextValue = Number.isFinite(asNumber) ? asNumber : nextValue;
      }
      this.$emit('update:modelValue', {
        attribute_key: attributeKey || '',
        value: nextValue,
      });
    },
    applyLiquidValue(token) {
      this.preferLiquidMode = true;
      this.$nextTick(() => {
        this.selectedValue = token;
      });
    },
    insertVariable(token) {
      const input = this.$refs.valueInput?.$el.querySelector('input');
      const current = String(this.selectedValue || '');
      const isFixedDate =
        /^\d{4}-\d{2}-\d{2}/.test(current) && !current.includes('{{');
      const from = isFixedDate ? 0 : (input?.selectionStart ?? current.length);
      const to = isFixedDate ? current.length : (input?.selectionEnd ?? from);
      this.preferLiquidMode = true;
      this.$nextTick(() => {
        this.selectedValue = `${current.slice(0, from)}${token}${current.slice(to)}`;
        this.$nextTick(() => {
          const field = this.$refs.valueInput?.$el.querySelector('input');
          field?.focus();
          field?.setSelectionRange(from + token.length, from + token.length);
        });
      });
    },
    buildRelativeLiquid(base, days) {
      const n = Math.min(
        MAX_RELATIVE_DAYS,
        Math.max(0, Number.parseInt(days, 10) || 0)
      );
      if (n === 0) return `{{ date.${base} }}`;
      return `{{ date.${base} | plus_days: ${n} }}`;
    },
    parseRelativeLiquid(value) {
      const text = String(value || '').trim();
      let match = text.match(/^\{\{\s*date\.(today|now)\s*\}\}$/);
      if (match) return { base: match[1], days: 0 };

      match = text.match(
        /^\{\{\s*date\.(today|now)\s*\|\s*plus_days:\s*(\d+)\s*\}\}$/
      );
      if (match) {
        return {
          base: match[1],
          days: Math.min(MAX_RELATIVE_DAYS, Number(match[2])),
        };
      }
      return { base: null, days: 0 };
    },
    applyRelativeDays(days) {
      this.applyLiquidValue(this.buildRelativeLiquid(this.relativeBase, days));
    },
    onRelativeDaysInput(raw) {
      const n = Math.min(
        MAX_RELATIVE_DAYS,
        Math.max(0, Number.parseInt(raw, 10) || 0)
      );
      this.applyRelativeDays(n);
    },
    useToday() {
      this.applyRelativeDays(0);
    },
    useNow() {
      this.applyLiquidValue(this.buildRelativeLiquid('now', 0));
    },
    useFixedDate() {
      this.preferLiquidMode = false;
      this.selectedValue = '';
    },
    presetChipClass(days) {
      const active = this.isRelativeLiquid && this.relativeDays === days;
      return [
        'inline-flex items-center justify-center h-7 px-2.5 rounded-lg text-xs font-medium',
        'outline outline-1 outline-offset-[-1px] transition-colors',
        active
          ? 'bg-n-brand/15 text-n-brand outline-n-brand'
          : 'bg-n-alpha-black2 text-n-slate-12 outline-n-weak hover:outline-n-slate-6',
      ].join(' ');
    },
  },
};
</script>

<template>
  <div
    class="flex flex-col gap-3 w-full mt-1 p-3 rounded-lg bg-n-solid-2 outline outline-1 outline-n-weak"
  >
    <div class="flex flex-col gap-1.5">
      <label class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_LABEL') }}
      </label>
      <div class="relative">
        <VariablePicker
          :model-value="targetPath"
          mode="write"
          surface="automation"
          write-context="automation"
          value-format="path"
          :scopes="[attributeModel.replace('_attribute', '')]"
          :filter="binding => binding.reference.kind === 'custom_attribute'"
          :placeholder="
            $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_SELECT_PLACEHOLDER')
          "
          @select="selectTarget"
        />
      </div>
      <p v-if="!attributeOptions.length" class="text-xs text-n-ruby-11 m-0">
        {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_EMPTY') }}
      </p>
    </div>

    <fieldset
      v-if="selectedKey"
      :disabled="!selectedAttribute"
      class="flex min-w-0 flex-col gap-1.5 border-0 p-0 m-0"
    >
      <label class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_VALUE_LABEL') }}
      </label>

      <div v-if="isListAttribute" class="relative">
        <ComboBox
          v-model="selectedValue"
          teleport
          :allow-deselect="false"
          :options="[
            ...(selectedAttribute?.values || []).map(option => ({
              value: option,
              label: option,
            })),
          ]"
          :placeholder="
            $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_SELECT_PLACEHOLDER')
          "
        />
      </div>

      <div v-else-if="isCheckboxAttribute" class="relative">
        <ComboBox
          v-model="selectedValue"
          teleport
          :allow-deselect="false"
          :options="[
            { value: 'true', label: $t('FILTER.ATTRIBUTE_LABELS.TRUE') },
            { value: 'false', label: $t('FILTER.ATTRIBUTE_LABELS.FALSE') },
          ]"
        />
      </div>

      <template
        v-else-if="isDateAttribute && valueUsesLiquid && isRelativeLiquid"
      >
        <div
          class="flex flex-col gap-2 rounded-lg bg-n-alpha-black2 px-3 py-2 outline outline-1 outline-n-weak"
        >
          <p class="text-sm text-n-slate-12 m-0">
            {{ relativeSummary }}
          </p>
          <p class="text-xs text-n-slate-11 m-0 font-mono">
            {{ selectedValue }}
          </p>
          <p class="text-xs text-n-slate-11 m-0">
            {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_DYNAMIC_HELP') }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              :class="presetChipClass(0)"
              @click="applyRelativeDays(0)"
            >
              {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_TODAY_CHIP') }}
            </button>
            <button
              v-for="days in dayPresets"
              :key="`date-preset-${days}`"
              type="button"
              :class="presetChipClass(days)"
              @click="applyRelativeDays(days)"
            >
              +{{ days }}
            </button>
            <label
              class="inline-flex items-center gap-1.5 text-xs text-n-slate-11"
            >
              <span>{{
                $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_DAYS_LABEL')
              }}</span>
              <input
                class="w-16 h-7 px-2 rounded-lg text-xs text-n-slate-12 bg-n-solid-2 outline outline-1 outline-n-weak focus:outline-n-brand"
                type="number"
                min="0"
                :max="365"
                :value="relativeDays"
                @change="onRelativeDaysInput($event.target.value)"
              />
            </label>
          </div>
          <div class="flex items-center gap-2">
            <NextButton
              xs
              faded
              slate
              :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_PICK_FIXED')"
              @click="useFixedDate"
            />
          </div>
        </div>
      </template>

      <template v-else-if="isDateAttribute && valueUsesLiquid">
        <NextInput
          ref="valueInput"
          v-model="selectedValue"
          type="text"
          size="sm"
          :placeholder="valuePlaceholder"
        />
        <p class="text-xs text-n-slate-11 m-0">
          {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_DYNAMIC_HELP') }}
        </p>
        <div class="flex items-center gap-2 flex-wrap">
          <NextButton
            xs
            faded
            slate
            :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_PICK_FIXED')"
            @click="useFixedDate"
          />
          <NextButton
            xs
            faded
            slate
            :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_USE_TODAY')"
            @click="useToday"
          />
        </div>
      </template>

      <template v-else-if="isDateAttribute">
        <NextInput
          ref="valueInput"
          v-model="selectedValue"
          type="date"
          size="sm"
        />
        <div class="flex flex-wrap items-center gap-2">
          <NextButton
            xs
            faded
            slate
            :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_USE_TODAY')"
            @click="useToday"
          />
          <button
            v-for="days in dayPresets"
            :key="`date-fixed-preset-${days}`"
            type="button"
            :class="presetChipClass(days)"
            @click="applyRelativeDays(days)"
          >
            +{{ days }}
          </button>
        </div>
      </template>

      <template
        v-else-if="isDatetimeAttribute && valueUsesLiquid && isRelativeLiquid"
      >
        <div
          class="flex flex-col gap-2 rounded-lg bg-n-alpha-black2 px-3 py-2 outline outline-1 outline-n-weak"
        >
          <p class="text-sm text-n-slate-12 m-0">
            {{ relativeSummary }}
          </p>
          <p class="text-xs text-n-slate-11 m-0 font-mono">
            {{ selectedValue }}
          </p>
          <p class="text-xs text-n-slate-11 m-0">
            {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATETIME_DYNAMIC_HELP') }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              :class="presetChipClass(0)"
              @click="applyRelativeDays(0)"
            >
              {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_NOW_CHIP') }}
            </button>
            <button
              v-for="days in dayPresets"
              :key="`datetime-preset-${days}`"
              type="button"
              :class="presetChipClass(days)"
              @click="applyRelativeDays(days)"
            >
              +{{ days }}
            </button>
            <label
              class="inline-flex items-center gap-1.5 text-xs text-n-slate-11"
            >
              <span>{{
                $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_RELATIVE_DAYS_LABEL')
              }}</span>
              <input
                class="w-16 h-7 px-2 rounded-lg text-xs text-n-slate-12 bg-n-solid-2 outline outline-1 outline-n-weak focus:outline-n-brand"
                type="number"
                min="0"
                :max="365"
                :value="relativeDays"
                @change="onRelativeDaysInput($event.target.value)"
              />
            </label>
          </div>
          <div class="flex items-center justify-between gap-2 flex-wrap">
            <NextButton
              xs
              faded
              slate
              :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_PICK_FIXED')"
              @click="useFixedDate"
            />
            <InsertVariableButton
              context="automation"
              @insert="insertVariable"
            />
          </div>
        </div>
      </template>

      <template v-else-if="isDatetimeAttribute && valueUsesLiquid">
        <NextInput
          ref="valueInput"
          v-model="selectedValue"
          type="text"
          size="sm"
          :placeholder="valuePlaceholder"
        />
        <p class="text-xs text-n-slate-11 m-0">
          {{ $t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATETIME_DYNAMIC_HELP') }}
        </p>
        <div class="flex items-center justify-between gap-2 flex-wrap">
          <NextButton
            xs
            faded
            slate
            :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_DATE_PICK_FIXED')"
            @click="useFixedDate"
          />
          <InsertVariableButton context="automation" @insert="insertVariable" />
        </div>
      </template>

      <template v-else-if="isDatetimeAttribute">
        <NextInput
          ref="valueInput"
          v-model="selectedValue"
          type="datetime-local"
          size="sm"
        />
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2">
            <NextButton
              xs
              faded
              slate
              :label="$t('AUTOMATION.ACTION.CUSTOM_ATTRIBUTE_USE_NOW')"
              @click="useNow"
            />
            <button
              v-for="days in dayPresets"
              :key="`datetime-fixed-preset-${days}`"
              type="button"
              :class="presetChipClass(days)"
              @click="applyRelativeDays(days)"
            >
              +{{ days }}
            </button>
          </div>
          <InsertVariableButton context="automation" @insert="insertVariable" />
        </div>
      </template>

      <template v-else>
        <NextInput
          ref="valueInput"
          v-model="selectedValue"
          :type="inputType"
          size="sm"
          :placeholder="valuePlaceholder"
        />
        <div
          v-if="showVariablePicker"
          class="flex items-center justify-end gap-2"
        >
          <InsertVariableButton context="automation" @insert="insertVariable" />
        </div>
      </template>
    </fieldset>
  </div>
</template>
