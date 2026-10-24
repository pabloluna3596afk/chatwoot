<script setup>
import { ref } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

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

const dialogRef = ref(null);
const onClickAdd = async () => {
  if (isSaving.value || !modelValue.value?.trim()) return;
  isSaving.value = true;
  try {
    if (await props.onAdd(modelValue.value.trim())) {
      modelValue.value = '';
      dialogRef.value.close();
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="inline-flex">
    <Button
      :label="buttonLabel"
      sm
      slate
      class="flex-shrink-0 min-h-11 sm:min-h-0"
      :disabled="isSaving"
      @click="dialogRef.open()"
    />
    <Dialog
      ref="dialogRef"
      width="sm"
      body-scroll
      :title="buttonLabel"
      :cancel-button-label="cancelLabel"
      :confirm-button-label="confirmLabel"
      :is-loading="isSaving"
      :disable-confirm-button="!modelValue.trim()"
      @confirm="onClickAdd"
    >
      <Input
        v-model="modelValue"
        :disabled="isSaving"
        class="[&_input]:min-h-11 sm:[&_input]:min-h-0"
        :label="buttonLabel"
        :placeholder="placeholder"
      />
      <template #footer>
        <div class="flex items-center gap-3">
          <Button
            :label="cancelLabel"
            variant="faded"
            color="slate"
            type="button"
            class="w-full min-h-11 sm:min-h-0"
            :disabled="isSaving"
            @click="dialogRef.close()"
          />
          <Button
            :label="confirmLabel"
            type="submit"
            class="w-full min-h-11 sm:min-h-0"
            :is-loading="isSaving"
            :disabled="isSaving || !modelValue.trim()"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
