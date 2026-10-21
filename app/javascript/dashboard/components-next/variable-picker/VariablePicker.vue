<script setup>
import { computed, defineAsyncComponent, ref, useAttrs } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { sanitizeVariableSearchKey } from 'dashboard/helper/commons';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  presentation: {
    type: String,
    default: 'field',
    validator: value => ['field', 'insert', 'caret'].includes(value),
  },
  caretPosition: { type: Object, default: null },
  searchKey: { type: String, default: '' },
  size: { type: String, default: 'sm' },
  showLabel: { type: Boolean, default: true },
  mode: {
    type: String,
    default: 'read',
    validator: value => ['read', 'write'].includes(value),
  },
  modelValue: { type: String, default: '' },
  surface: { type: String, default: 'message' },
  writeContext: { type: String, default: 'whatsapp_flow' },
  valueFormat: {
    type: String,
    default: 'id',
    validator: value => ['id', 'alias', 'path'].includes(value),
  },
  scopes: {
    type: Array,
    default: () => [
      'system',
      'contact',
      'conversation',
      'appointment',
      'assistant',
      'company',
      'flow',
    ],
  },
  filter: { type: Function, default: () => true },
  allowNone: { type: Boolean, default: false },
  allowNoneLabel: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:modelValue',
  'select',
  'close',
  'removeTrigger',
]);
defineOptions({ inheritAttrs: false });
const { t, te } = useI18n();
const { bindings, status, refresh } = useTemplateBindings(() => props.surface);
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');
const store = useStore();
const AddAttribute = defineAsyncComponent(
  () =>
    import('dashboard/routes/dashboard/settings/attributes/AddAttribute.vue')
);
const showAddAttribute = ref(false);
const searchQuery = ref(sanitizeVariableSearchKey(props.searchKey));
const closeAddAttribute = async () => {
  showAddAttribute.value = false;
  await store.dispatch('attributes/get');
  await refresh();
};
const SCOPE_ORDER = [
  'system',
  'contact',
  'conversation',
  'appointment',
  'assistant',
  'company',
  'flow',
];
const catalog = bindings;
const eligible = computed(() =>
  catalog.value.filter(
    binding =>
      props.scopes.includes(binding.scope) &&
      (props.mode === 'read'
        ? binding.readable
        : binding.writable &&
          !binding.managedBy &&
          binding.writeContexts.includes(props.writeContext)) &&
      props.filter(binding)
  )
);
const labelFor = binding => {
  if (binding.reference.kind === 'custom_attribute') return binding.label;
  const aliasKey = `VARIABLE_PICKER.LABELS.${binding.name}`;
  const pathKey = `VARIABLES.LABELS.${binding.reference.path}`;
  if (te(aliasKey)) return t(aliasKey);
  return te(pathKey) ? t(pathKey) : binding.label;
};
const valueFor = binding => {
  if (props.valueFormat === 'alias') return binding.name;
  if (props.valueFormat === 'path') return binding.canonicalPath;
  return binding.id;
};
const select = value => {
  emit('update:modelValue', value);
  const binding = eligible.value.find(item => valueFor(item) === value);
  if (binding) emit('select', binding);
};
const unknown = computed(
  () =>
    status.value === 'ready' &&
    props.modelValue &&
    !eligible.value.some(binding => valueFor(binding) === props.modelValue)
);
const options = computed(() => [
  ...(props.allowNone
    ? [{ value: '', label: props.allowNoneLabel || t('VARIABLE_PICKER.NONE') }]
    : []),
  ...eligible.value
    .filter(
      (binding, index, all) =>
        props.valueFormat === 'alias' ||
        all.findIndex(item => item.id === binding.id) === index
    )
    .map(binding => ({
      value: valueFor(binding),
      label:
        props.valueFormat === 'alias'
          ? `${labelFor(binding)} (${binding.name})`
          : labelFor(binding),
      group: binding.scope,
    })),
]);
const caretItems = computed(() => {
  const search = searchQuery.value.trim().toLowerCase();
  return options.value
    .map(option => {
      const binding = eligible.value.find(
        item => valueFor(item) === option.value
      );
      return {
        id: option.value,
        label: option.label,
        title: option.label,
        subtitle: binding.expression,
        group: t(`VARIABLE_PICKER.GROUPS.${binding.scope.toUpperCase()}`),
      };
    })
    .filter(item =>
      `${item.label} ${item.title}`.toLowerCase().includes(search)
    );
});
const groups = computed(() =>
  SCOPE_ORDER.filter(
    scope =>
      props.scopes.includes(scope) &&
      eligible.value.some(binding => binding.scope === scope)
  ).map(scope => ({
    key: scope,
    label: t(`VARIABLE_PICKER.GROUPS.${scope.toUpperCase()}`),
    emptyState: t(
      catalog.value.some(binding => binding.scope === scope)
        ? 'VARIABLE_PICKER.NO_COMPATIBLE'
        : 'VARIABLE_PICKER.NO_ATTRIBUTES'
    ),
  }))
);
// The list floats over the screen like every ChatHub menu: it never takes room in the form nor covers its footer.
const attrs = useAttrs();
const comboAttrs = computed(() => {
  const { class: className, ...rest } = attrs;
  return rest;
});
const placeholder = computed(
  () => attrs.placeholder || t('VARIABLE_PICKER.PLACEHOLDER')
);
</script>

<template>
  <div class="w-full min-w-0 text-n-slate-12" :class="$attrs.class">
    <CaretAnchoredPicker
      v-if="presentation === 'caret'"
      v-model:search="searchQuery"
      :caret-position="caretPosition"
      :items="status === 'ready' ? caretItems : []"
      :is-loading="status === 'loading'"
      :search-placeholder="$t('VARIABLE_PICKER.SEARCH')"
      :empty-label="$t('VARIABLE_PICKER.EMPTY')"
      @select="select($event.id)"
      @close="emit('close')"
      @remove-trigger="emit('removeTrigger')"
    >
      <template #filters>
        <div
          v-if="status === 'error'"
          role="alert"
          class="p-3 text-sm text-n-ruby-11"
        >
          {{ $t('VARIABLE_PICKER.ERROR') }}
          <Button
            type="button"
            sm
            ghost
            :label="$t('VARIABLE_PICKER.RETRY')"
            @click="refresh"
          />
        </div>
      </template>
    </CaretAnchoredPicker>
    <p
      v-if="presentation !== 'caret' && status === 'loading'"
      role="status"
      class="mb-2 text-sm text-n-slate-11"
    >
      {{ $t('VARIABLE_PICKER.LOADING') }}
    </p>
    <div
      v-if="presentation !== 'caret' && status === 'error'"
      role="alert"
      class="mb-2 text-sm text-n-ruby-11"
    >
      {{ $t('VARIABLE_PICKER.ERROR') }}
      <Button
        type="button"
        sm
        ghost
        :label="$t('VARIABLE_PICKER.RETRY')"
        @click="refresh"
      />
    </div>
    <ComboBox
      v-if="presentation !== 'caret'"
      v-bind="comboAttrs"
      :model-value="modelValue"
      :reset-on-select="presentation === 'insert'"
      :options="options"
      :groups="groups"
      :disabled="disabled || status === 'loading' || status === 'error'"
      :display-label="modelValue"
      :message="unknown ? $t('VARIABLE_PICKER.UNKNOWN') : ''"
      :has-error="hasError || Boolean(unknown)"
      :placeholder="placeholder"
      :search-placeholder="$t('VARIABLE_PICKER.SEARCH')"
      :empty-state="$t('VARIABLE_PICKER.EMPTY')"
      teleport
      menu-min-width="17rem"
      dropdown-max-height="max-h-80"
      show-search
      @close="emit('close')"
      @update:model-value="select($event)"
    >
      <template v-if="presentation === 'insert'" #trigger="{ toggle, open }">
        <Button
          type="button"
          :size="size"
          ghost
          slate
          icon="i-lucide-braces"
          :label="showLabel ? placeholder : ''"
          :aria-label="placeholder"
          aria-haspopup="listbox"
          :aria-expanded="open"
          :disabled="disabled || status === 'loading' || status === 'error'"
          @click="toggle"
        />
      </template>
      <template v-if="isAdmin" #footer="{ close }">
        <Button
          type="button"
          ghost
          slate
          sm
          class="w-full justify-start"
          icon="i-lucide-plus"
          :label="$t('VARIABLE_PICKER.CREATE_ATTRIBUTE')"
          data-testid="variable-create-attribute"
          @click="
            close();
            showAddAttribute = true;
          "
        />
      </template>
    </ComboBox>
    <AddAttribute
      v-if="showAddAttribute"
      :selected-attribute-model-tab="1"
      :on-close="closeAddAttribute"
    />
  </div>
</template>
