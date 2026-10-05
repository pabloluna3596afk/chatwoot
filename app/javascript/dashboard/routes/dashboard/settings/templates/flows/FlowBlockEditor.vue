<script setup>
// One block of a screen: its text or question, the options of a choice, the files allowed and the condition that shows
// it. It never changes the block it receives: every edit goes out as a new block.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import {
  BLOCK_TYPES,
  INPUT_KINDS,
  LIMITS,
  OPTION_TYPES,
  TEXT_TYPES,
  conditionSources,
  defaultCondition,
  fieldsOf,
  isAnswer,
  labelLimit,
  newOption,
  optionIdFor,
  textLimit,
  uniqueKey,
} from './flowDefinition';

const props = defineProps({
  modelValue: { type: Object, required: true },
  definition: { type: Object, required: true },
  screenIndex: { type: Number, required: true },
  blockIndex: { type: Number, required: true },
  isFirst: { type: Boolean, default: false },
  isLast: { type: Boolean, default: false },
  errors: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue', 'remove', 'move']);

const { t, te } = useI18n();

const icon = computed(
  () => BLOCK_TYPES.find(item => item.type === props.modelValue.type)?.icon
);
const isText = computed(() => TEXT_TYPES.includes(props.modelValue.type));
const hasOptions = computed(() => OPTION_TYPES.includes(props.modelValue.type));
const isFile = computed(() =>
  ['photo', 'document'].includes(props.modelValue.type)
);
const hasHelper = computed(
  () => isAnswer(props.modelValue) && props.modelValue.type !== 'optin'
);

const patch = changes =>
  emit('update:modelValue', { ...props.modelValue, ...changes });

const otherKeys = computed(() =>
  fieldsOf(props.definition)
    .filter(
      field =>
        !(
          field.screen === props.screenIndex && field.block === props.blockIndex
        )
    )
    .map(field => field.key)
);

// The name of the answer follows the label until someone sets it by hand.
const onLabel = value => {
  const automatic =
    !props.modelValue.label ||
    props.modelValue.key === uniqueKey(props.modelValue.label, otherKeys.value);
  patch({
    label: value,
    ...(automatic && value ? { key: uniqueKey(value, otherKeys.value) } : {}),
  });
};

const onOptionTitle = (index, title) => {
  const options = props.modelValue.options.map((option, position) =>
    position === index
      ? { ...option, title, id: optionIdFor(title, props.modelValue, index) }
      : option
  );
  patch({ options });
};

const addOption = () =>
  patch({
    options: [...props.modelValue.options, newOption(props.modelValue)],
  });
const removeOption = index =>
  patch({
    options: props.modelValue.options.filter(
      (_, position) => position !== index
    ),
  });

const sources = computed(() =>
  conditionSources(props.definition, props.screenIndex, props.blockIndex)
);
const hasCondition = computed(() => Boolean(props.modelValue.visible_when));
const condition = computed(() => props.modelValue.visible_when || {});
const source = computed(() =>
  sources.value.find(field => field.key === condition.value.key)
);

const toggleCondition = enabled => {
  if (!enabled) {
    const rest = { ...props.modelValue };
    delete rest.visible_when;
    emit('update:modelValue', rest);
  } else if (sources.value.length) {
    patch({ visible_when: defaultCondition(sources.value[0]) });
  }
};

const setConditionField = key => {
  const field = sources.value.find(item => item.key === key);
  if (field) patch({ visible_when: defaultCondition(field) });
};
const setCondition = changes =>
  patch({ visible_when: { ...condition.value, ...changes } });

const sourceOptions = computed(() =>
  sources.value.map(field => ({
    value: field.key,
    label: field.definition.label || field.key,
  }))
);
const operatorOptions = computed(() => [
  { value: 'equals', label: t('WHATSAPP_FLOWS.EDITOR.OPS.equals') },
  { value: 'not_equals', label: t('WHATSAPP_FLOWS.EDITOR.OPS.not_equals') },
]);
const valueOptions = computed(() => {
  if (source.value?.type === 'optin')
    return [
      { value: 'true', label: t('WHATSAPP_FLOWS.EDITOR.CHECKED') },
      { value: 'false', label: t('WHATSAPP_FLOWS.EDITOR.UNCHECKED') },
    ];
  return (source.value?.definition.options || []).map(option => ({
    value: option.id,
    label: option.title || option.id,
  }));
});
const valueIsFree = computed(() => source.value?.type === 'short_text');
const kindOptions = computed(() =>
  INPUT_KINDS.map(kind => ({
    value: kind,
    label: t(`WHATSAPP_FLOWS.EDITOR.KINDS.${kind}`),
  }))
);

const errorText = error => {
  const key = `WHATSAPP_FLOWS.ERRORS.${error.code}`;
  return te(key) ? t(key, error.details || {}) : error.code;
};

const keepValue = (apply, value) => {
  if (value) apply(value);
};
</script>

<template>
  <div
    class="flex flex-col gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-1"
    :class="{ 'outline outline-1 outline-n-ruby-8': errors.length }"
    data-testid="flow-block"
  >
    <div class="flex items-center gap-2">
      <span :class="icon" class="size-4 text-n-slate-11" />
      <span class="flex-1 text-sm font-medium text-n-slate-12">
        {{ $t(`WHATSAPP_FLOWS.BLOCKS.${modelValue.type}`) }}
      </span>
      <Button
        type="button"
        ghost
        slate
        xs
        icon="i-lucide-arrow-up"
        :disabled="isFirst"
        :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_UP')"
        @click="emit('move', -1)"
      />
      <Button
        type="button"
        ghost
        slate
        xs
        icon="i-lucide-arrow-down"
        :disabled="isLast"
        :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_DOWN')"
        @click="emit('move', 1)"
      />
      <Button
        type="button"
        ghost
        ruby
        xs
        icon="i-lucide-trash-2"
        :aria-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK')"
        data-testid="flow-block-remove"
        @click="emit('remove')"
      />
    </div>

    <TextArea
      v-if="isText"
      :model-value="modelValue.text"
      :max-length="textLimit(modelValue.type)"
      :placeholder="$t('WHATSAPP_FLOWS.EDITOR.TEXT_PLACEHOLDER')"
      @update:model-value="patch({ text: $event })"
    />

    <template v-else>
      <Input
        :model-value="modelValue.label"
        :placeholder="$t('WHATSAPP_FLOWS.EDITOR.LABEL_PLACEHOLDER')"
        :max-length="labelLimit(modelValue.type)"
        data-testid="flow-block-label"
        @update:model-value="onLabel"
      />
      <div v-if="hasHelper" class="grid gap-1">
        <Input
          :model-value="modelValue.helper || ''"
          size="sm"
          :placeholder="$t('WHATSAPP_FLOWS.EDITOR.HELPER_PLACEHOLDER')"
          :max-length="LIMITS.helper"
          @update:model-value="patch({ helper: $event })"
        />
      </div>

      <div v-if="modelValue.type === 'short_text'" class="grid gap-1">
        <span class="text-xs text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.EDITOR.INPUT_KIND') }}
        </span>
        <ComboBox
          :model-value="modelValue.input || 'text'"
          :options="kindOptions"
          @update:model-value="
            keepValue(value => patch({ input: value }), $event)
          "
        />
      </div>

      <div v-if="hasOptions" class="grid gap-2" data-testid="flow-options">
        <span class="text-xs text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.EDITOR.OPTIONS') }}
        </span>
        <div
          v-for="(option, index) in modelValue.options"
          :key="index"
          class="flex items-center gap-2"
        >
          <Input
            class="flex-1"
            size="sm"
            :model-value="option.title"
            :max-length="LIMITS.optionTitle"
            :placeholder="$t('WHATSAPP_FLOWS.EDITOR.OPTION_PLACEHOLDER')"
            @update:model-value="onOptionTitle(index, $event)"
          />
          <Button
            type="button"
            ghost
            slate
            xs
            icon="i-lucide-x"
            :disabled="modelValue.options.length <= 1"
            :aria-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_OPTION')"
            @click="removeOption(index)"
          />
        </div>
        <div>
          <Button
            type="button"
            slate
            xs
            icon="i-lucide-plus"
            :label="$t('WHATSAPP_FLOWS.EDITOR.ADD_OPTION')"
            data-testid="flow-option-add"
            @click="addOption"
          />
        </div>
        <div
          v-if="modelValue.type === 'checkbox'"
          class="grid grid-cols-2 gap-2"
        >
          <Input
            size="sm"
            type="number"
            :label="$t('WHATSAPP_FLOWS.EDITOR.MIN_CHOICES')"
            :model-value="String(modelValue.min || '')"
            @update:model-value="patch({ min: Number($event) || 0 })"
          />
          <Input
            size="sm"
            type="number"
            :label="$t('WHATSAPP_FLOWS.EDITOR.MAX_CHOICES')"
            :model-value="String(modelValue.max || '')"
            @update:model-value="patch({ max: Number($event) || 0 })"
          />
        </div>
      </div>

      <Input
        v-if="isFile"
        size="sm"
        type="number"
        :label="$t('WHATSAPP_FLOWS.EDITOR.MAX_FILES')"
        :model-value="String(modelValue.max_files || 1)"
        @update:model-value="patch({ max_files: Number($event) || 1 })"
      />

      <div class="flex items-center gap-2">
        <Switch
          :model-value="modelValue.required === true"
          @update:model-value="patch({ required: $event })"
        />
        <span class="text-sm text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.EDITOR.REQUIRED') }}
        </span>
      </div>

      <Input
        size="sm"
        :model-value="modelValue.key"
        :label="$t('WHATSAPP_FLOWS.EDITOR.KEY')"
        :message="$t('WHATSAPP_FLOWS.EDITOR.KEY_HELP')"
        data-testid="flow-block-key"
        @update:model-value="patch({ key: $event })"
      />
    </template>

    <div class="grid gap-2">
      <div class="flex items-center gap-2">
        <Switch
          :model-value="hasCondition"
          :disabled="!hasCondition && !sources.length"
          data-testid="flow-condition-toggle"
          @update:model-value="toggleCondition"
        />
        <span class="text-sm text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.EDITOR.CONDITION') }}
        </span>
      </div>
      <p
        v-if="!hasCondition && !sources.length"
        class="text-xs text-n-slate-11"
      >
        {{ $t('WHATSAPP_FLOWS.EDITOR.CONDITION_NEEDS_ANSWER') }}
      </p>
      <div
        v-if="hasCondition"
        class="grid gap-2 sm:grid-cols-3"
        data-testid="flow-condition"
      >
        <ComboBox
          :model-value="condition.key"
          :options="sourceOptions"
          @update:model-value="keepValue(setConditionField, $event)"
        />
        <ComboBox
          :model-value="condition.op"
          :options="operatorOptions"
          @update:model-value="
            keepValue(value => setCondition({ op: value }), $event)
          "
        />
        <Input
          v-if="valueIsFree"
          size="sm"
          :model-value="condition.value"
          @update:model-value="setCondition({ value: $event })"
        />
        <ComboBox
          v-else
          :model-value="condition.value"
          :options="valueOptions"
          @update:model-value="
            keepValue(value => setCondition({ value }), $event)
          "
        />
      </div>
    </div>

    <ul v-if="errors.length" class="grid gap-1 text-xs text-n-ruby-11">
      <li v-for="error in errors" :key="`${error.code}-${error.path}`">
        {{ errorText(error) }}
      </li>
    </ul>
  </div>
</template>
