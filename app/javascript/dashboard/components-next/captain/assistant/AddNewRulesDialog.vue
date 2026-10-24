<script setup>
import { ref } from 'vue';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

const props = defineProps({
  // Return true only after the mutation succeeds; events cannot be awaited.
  onAdd: { type: Function, required: true },
  placeholder: {
    type: String,
    default: '',
  },
  buttonLabel: {
    type: String,
    default: '',
  },
  confirmLabel: {
    type: String,
    default: '',
  },
  cancelLabel: {
    type: String,
    default: '',
  },
});

const isSaving = ref(false);

const modelValue = defineModel({
  type: String,
  default: '',
});

const [showPopover, togglePopover] = useToggle();
const onClickAdd = async () => {
  if (isSaving.value || !modelValue.value?.trim()) return;
  isSaving.value = true;
  try {
    if (await props.onAdd(modelValue.value.trim())) {
      modelValue.value = '';
      togglePopover(false);
    }
  } finally {
    isSaving.value = false;
  }
};

const onClickCancel = () => {
  if (!isSaving.value) togglePopover(false);
};
</script>

<template>
  <div v-on-click-outside="onClickCancel" class="inline-flex relative">
    <Button
      :label="buttonLabel"
      sm
      slate
      class="flex-shrink-0"
      :disabled="isSaving"
      @click="togglePopover(!showPopover)"
    />
    <div
      v-if="showPopover"
      class="absolute w-[26.5rem] top-9 z-50 ltr:left-0 rtl:right-0 flex flex-col gap-5 bg-n-alpha-3 backdrop-blur-[100px] p-4 rounded-xl border border-n-weak shadow-md"
    >
      <InlineInput
        v-model="modelValue"
        :disabled="isSaving"
        :placeholder="placeholder"
        @keyup.enter="onClickAdd"
      />
      <div class="flex gap-2 justify-between">
        <Button
          :label="cancelLabel"
          sm
          link
          slate
          class="h-10 hover:!no-underline"
          @click="onClickCancel"
        />
        <Button
          :label="confirmLabel"
          sm
          :is-loading="isSaving"
          :disabled="isSaving"
          @click="onClickAdd"
        />
      </div>
    </div>
  </div>
</template>
