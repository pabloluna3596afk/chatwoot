<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';

defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  message: { type: String, default: '' },
  surface: { type: String, default: 'message' },
  filter: { type: Function, default: () => true },
});
const emit = defineEmits(['update:modelValue', 'select']);
</script>

<template>
  <Input
    :model-value="modelValue"
    :placeholder="placeholder"
    :message="message"
    custom-input-class="!flex-none !min-h-11 !pe-12 sm:!min-h-10 sm:!pe-11"
    @update:model-value="emit('update:modelValue', $event)"
  >
    <template #prefix>
      <VariablePicker
        presentation="insert"
        :show-label="false"
        :surface="surface"
        :filter="filter"
        :placeholder="$t('VARIABLES.INSERT_IN_FIELD')"
        :title="$t('VARIABLES.INSERT_IN_FIELD')"
        class="absolute end-0 top-0 !w-11 sm:!w-10 [&_button[aria-haspopup=listbox]]:!size-11 sm:[&_button[aria-haspopup=listbox]]:!size-10"
        @select="emit('select', $event)"
      />
    </template>
  </Input>
</template>
