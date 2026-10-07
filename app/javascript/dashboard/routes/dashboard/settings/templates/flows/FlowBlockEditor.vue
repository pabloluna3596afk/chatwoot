<script setup>
// The settings of the selected block (the right column of the builder): its text or question, the options of a choice,
// the files allowed and the condition that shows it. It never changes the block it receives: every edit goes out as a
// new block.
import { computed, defineAsyncComponent, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { saveTargets } from './flowSaveTargets';
import {
  INPUT_KINDS,
  LIMITS,
  OPTION_TYPES,
  SINGLE_CHOICE_TYPES,
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
  errors: { type: Array, default: () => [] },
  attributes: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t, te } = useI18n();
const AddAttribute = defineAsyncComponent(
  () =>
    import('dashboard/routes/dashboard/settings/attributes/AddAttribute.vue')
);
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');
const store = useStore();
const showAddAttribute = ref(false);
const closeAddAttribute = async () => {
  showAddAttribute.value = false;
  await store.dispatch('attributes/get');
};

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

const targets = computed(() => saveTargets(props.modelValue, props.attributes));
const targetOptions = computed(() => [
  { value: '', label: t('WHATSAPP_FLOWS.EDITOR.NO_SAVE') },
  ...targets.value.map(target => ({
    value: target.key,
    label:
      target.group === 'system'
        ? t(`WHATSAPP_FLOWS.EDITOR.TARGETS.${target.name}`)
        : target.label,
    group: target.group,
  })),
]);
const targetGroups = computed(() => [
  { key: 'system', label: t('WHATSAPP_FLOWS.EDITOR.CONTACT') },
  {
    key: 'contact',
    label: t('WHATSAPP_FLOWS.EDITOR.CUSTOM_ATTRIBUTES'),
    emptyState: t(
      props.attributes.some(
        attribute => attribute.attribute_model === 'contact_attribute'
      )
        ? 'WHATSAPP_FLOWS.EDITOR.NO_COMPATIBLE_ATTRIBUTES'
        : 'WHATSAPP_FLOWS.EDITOR.NO_CUSTOM_ATTRIBUTES'
    ),
  },
]);
const setSaveTo = target => {
  const block = { ...props.modelValue };
  if (target) block.save_to = { target };
  else delete block.save_to;
  emit('update:modelValue', block);
};

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

// The questions a condition can look at: the pick-one questions before this block (and the one it already uses).
const sources = computed(() =>
  conditionSources(
    props.definition,
    props.screenIndex,
    props.blockIndex
  ).filter(
    field =>
      SINGLE_CHOICE_TYPES.includes(field.type) ||
      field.key === props.modelValue.visible_when?.key
  )
);
const hasCondition = computed(() => Boolean(props.modelValue.visible_when));
const condition = computed(() => props.modelValue.visible_when || {});
const source = computed(() =>
  sources.value.find(field => field.key === condition.value.key)
);

const showOptions = computed(() => [
  { value: '', label: t('WHATSAPP_FLOWS.EDITOR.SHOW_ALWAYS') },
  ...sources.value.map(field => ({
    value: field.key,
    label: t('WHATSAPP_FLOWS.EDITOR.SHOW_IF', {
      question: field.definition.label || field.key,
    }),
  })),
]);

const setShow = key => {
  if (!key) {
    const rest = { ...props.modelValue };
    delete rest.visible_when;
    emit('update:modelValue', rest);
    return;
  }
  const field = sources.value.find(item => item.key === key);
  // A field that can be hidden cannot be required (Meta refuses it).
  if (field)
    patch({
      visible_when: defaultCondition(field),
      ...(hasCondition.value ? {} : { required: false }),
    });
};
const setCondition = changes =>
  patch({ visible_when: { ...condition.value, ...changes } });

const operatorOptions = computed(() => [
  { value: 'equals', label: t('WHATSAPP_FLOWS.EDITOR.OPS.equals') },
  { value: 'not_equals', label: t('WHATSAPP_FLOWS.EDITOR.OPS.not_equals') },
]);
const valueOptions = computed(() =>
  (source.value?.definition.options || []).map(option => ({
    value: option.id,
    label: option.title || option.id,
  }))
);
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
  <div class="flex flex-col gap-3" data-testid="flow-block">
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
      <div v-if="!isFile" class="grid gap-1.5 text-sm text-n-slate-12">
        <span>{{ $t('WHATSAPP_FLOWS.EDITOR.SAVE_TO') }}</span>
        <ComboBox
          :model-value="modelValue.save_to?.target || ''"
          :options="targetOptions"
          :aria-label="$t('WHATSAPP_FLOWS.EDITOR.SAVE_TO')"
          :groups="targetGroups"
          teleport
          show-search
          :search-placeholder="$t('WHATSAPP_FLOWS.EDITOR.SEARCH_SAVE_TARGETS')"
          data-testid="flow-save-to"
          @update:model-value="setSaveTo"
        >
          <template v-if="isAdmin" #footer="{ close }">
            <Button
              type="button"
              ghost
              slate
              sm
              class="w-full justify-start"
              icon="i-lucide-plus"
              :label="$t('WHATSAPP_FLOWS.EDITOR.CREATE_CUSTOM_ATTRIBUTE')"
              data-testid="flow-create-attribute"
              @click="
                close();
                showAddAttribute = true;
              "
            />
          </template>
        </ComboBox>
      </div>
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
        data-testid="flow-block-key"
        @update:model-value="patch({ key: $event })"
      />
      <p class="m-0 -mt-2 text-xs text-n-slate-11" data-testid="flow-key-help">
        {{ $t('WHATSAPP_FLOWS.EDITOR.KEY_HELP') }}
      </p>
    </template>

    <div class="grid gap-2" data-testid="flow-condition">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('WHATSAPP_FLOWS.EDITOR.SHOW_FIELD') }}
      </span>
      <ComboBox
        :model-value="condition.key || ''"
        :options="showOptions"
        data-testid="flow-show"
        @update:model-value="setShow($event || '')"
      />
      <p
        v-if="!sources.length"
        class="text-xs text-n-slate-11"
        data-testid="flow-condition-hint"
      >
        {{ $t('WHATSAPP_FLOWS.EDITOR.SHOW_NEEDS_QUESTION') }}
      </p>
      <template v-if="hasCondition">
        <div class="grid grid-cols-2 gap-2">
          <ComboBox
            :model-value="condition.op"
            :options="operatorOptions"
            @update:model-value="
              keepValue(value => setCondition({ op: value }), $event)
            "
          />
          <ComboBox
            :model-value="condition.value"
            :options="valueOptions"
            data-testid="flow-show-value"
            @update:model-value="
              keepValue(value => setCondition({ value }), $event)
            "
          />
        </div>
      </template>
    </div>

    <ul v-if="errors.length" class="grid gap-1 text-xs text-n-ruby-11">
      <li v-for="error in errors" :key="`${error.code}-${error.path}`">
        {{ errorText(error) }}
      </li>
    </ul>
    <AddAttribute
      v-if="showAddAttribute"
      :selected-attribute-model-tab="1"
      :on-close="closeAddAttribute"
    />
  </div>
</template>
