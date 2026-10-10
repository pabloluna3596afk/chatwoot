<script setup>
import { computed, defineAsyncComponent, ref, useAttrs } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { APPOINTMENT_BINDINGS } from 'dashboard/helper/templateVariableBindings';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'read',
    validator: value => ['read', 'write'].includes(value),
  },
  modelValue: { type: String, default: '' },
  scopes: {
    type: Array,
    default: () => ['system', 'contact', 'conversation', 'appointment'],
  },
  filter: { type: Function, default: () => true },
  allowNone: { type: Boolean, default: false },
  allowNoneLabel: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
  // Flow already has account definitions; other consumers use the shared composable.
  attributes: { type: Array, default: null },
});
const emit = defineEmits(['update:modelValue']);
defineOptions({ inheritAttrs: false });
const { t } = useI18n();
const { bindings } = useTemplateBindings(
  'message',
  computed(() => props.attributes)
);
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
};
const SCOPE_ORDER = ['system', 'contact', 'conversation', 'appointment'];
const catalog = computed(() => {
  const known = new Set(bindings.value.map(binding => binding.name));
  return [
    ...bindings.value,
    ...APPOINTMENT_BINDINGS.filter(binding => !known.has(binding.name)),
  ];
});
const eligible = computed(() =>
  catalog.value.filter(
    binding =>
      props.scopes.includes(binding.scope) &&
      (props.mode === 'read' ? binding.readable : binding.writable) &&
      props.filter(binding)
  )
);
const labelFor = binding => {
  const label = binding.label || t(`VARIABLE_PICKER.LABELS.${binding.name}`);
  return props.mode === 'read' ? `${label} (${binding.name})` : label;
};
const options = computed(() => [
  ...(props.allowNone
    ? [{ value: '', label: props.allowNoneLabel || t('VARIABLE_PICKER.NONE') }]
    : []),
  ...eligible.value.map(binding => ({
    value: props.mode === 'read' ? binding.name : binding.canonicalPath,
    label: labelFor(binding),
    group: binding.scope,
  })),
]);
const groups = computed(() =>
  SCOPE_ORDER.filter(scope => props.scopes.includes(scope)).map(scope => ({
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
const placeholder = computed(
  () => attrs.placeholder || t('VARIABLE_PICKER.PLACEHOLDER')
);
</script>

<template>
  <div class="w-full min-w-0 text-n-slate-12">
    <ComboBox
      v-bind="$attrs"
      :model-value="modelValue"
      :options="options"
      :groups="groups"
      :disabled="disabled"
      :has-error="hasError"
      :placeholder="placeholder"
      :search-placeholder="$t('VARIABLE_PICKER.SEARCH')"
      :empty-state="$t('VARIABLE_PICKER.EMPTY')"
      teleport
      menu-min-width="17rem"
      show-search
      @update:model-value="emit('update:modelValue', $event)"
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
