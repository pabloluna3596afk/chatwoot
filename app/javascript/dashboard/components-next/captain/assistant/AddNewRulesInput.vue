<script setup>
import { ref } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

const props = defineProps({
  // Return true only after the mutation succeeds; events cannot be awaited.
  onAdd: { type: Function, required: true },
  placeholder: {
    type: String,
    default: '',
  },
  label: {
    type: String,
    default: '',
  },
  maxLength: {
    type: Number,
    default: null,
  },
});

const isSaving = ref(false);

const modelValue = defineModel({
  type: String,
  default: '',
});

const onClickAdd = async () => {
  if (isSaving.value || !modelValue.value?.trim()) return;
  isSaving.value = true;
  try {
    if (await props.onAdd(modelValue.value.trim())) {
      modelValue.value = '';
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="flex h-16 items-center gap-3 rounded-xl bg-n-solid-2 py-3 ps-3 pe-4 outline outline-1 outline-n-container -outline-offset-1"
  >
    <Icon icon="i-lucide-plus" class="text-n-slate-10 size-5 flex-shrink-0" />

    <InlineInput
      v-model="modelValue"
      :disabled="isSaving"
      :placeholder="placeholder"
      :max-length="maxLength"
      @keyup.enter="onClickAdd"
    />
    <Button
      :label="label"
      ghost
      xs
      slate
      class="!text-sm !text-n-slate-11 flex-shrink-0"
      :is-loading="isSaving"
      :disabled="isSaving"
      @click="onClickAdd"
    />
  </div>
</template>
