<script setup>
import { computed, defineAsyncComponent, ref, useAttrs } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
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
const emit = defineEmits(['update:modelValue', 'select']);
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
    <p
      v-if="status === 'loading'"
      role="status"
      class="mb-2 text-sm text-n-slate-11"
    >
      {{ $t('VARIABLE_PICKER.LOADING') }}
    </p>
    <div
      v-if="status === 'error'"
      role="alert"
      class="mb-2 text-sm text-n-ruby-11"
    >
      {{ $t('VARIABLE_PICKER.ERROR') }}
      <Button sm ghost :label="$t('VARIABLE_PICKER.RETRY')" @click="refresh" />
    </div>
    <ComboBox
      v-bind="comboAttrs"
      :model-value="modelValue"
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
      show-search
      @update:model-value="select($event)"
    >
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
