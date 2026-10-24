<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

const props = defineProps({
  // Return true only after the mutation succeeds; events cannot be awaited.
  onAdd: { type: Function, required: true },
});
const isSaving = ref(false);

const { t } = useI18n();

const dialogRef = ref(null);

const state = reactive({
  id: '',
  title: '',
  description: '',
  instruction: '',
});

const rules = {
  title: { required, minLength: minLength(1) },
  description: { required },
  instruction: { required },
};

const v$ = useVuelidate(rules, state);

const titleError = computed(() =>
  v$.value.title.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.ERROR')
    : ''
);

const descriptionError = computed(() =>
  v$.value.description.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.ERROR')
    : ''
);

const instructionError = computed(() =>
  v$.value.instruction.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.ERROR')
    : ''
);

const resetState = () => {
  Object.assign(state, {
    id: '',
    title: '',
    description: '',
    instruction: '',
  });
};

const onClickAdd = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  if (isSaving.value) return;
  isSaving.value = true;
  try {
    if (await props.onAdd({ ...state })) {
      resetState();
      v$.value.$reset();
      dialogRef.value.close();
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="inline-flex relative">
    <Button
      :label="t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.CREATE')"
      sm
      slate
      class="flex-shrink-0"
      :disabled="isSaving"
      @click="dialogRef.open()"
    />

    <Dialog
      ref="dialogRef"
      :title="t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.TITLE')"
      :is-loading="isSaving"
      :confirm-button-label="
        t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.CREATE')
      "
      :cancel-button-label="
        t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.CANCEL')
      "
      body-scroll
      @confirm="onClickAdd"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="state.title"
          :disabled="isSaving"
          :label="t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.LABEL')"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.PLACEHOLDER')
          "
          :message="titleError"
          :message-type="titleError ? 'error' : 'info'"
        />

        <TextArea
          v-model="state.description"
          :disabled="isSaving"
          :max-length="500"
          :label="
            t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.LABEL')
          "
          :placeholder="
            t(
              'CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.PLACEHOLDER'
            )
          "
          :message="descriptionError"
          :message-type="descriptionError ? 'error' : 'info'"
          show-character-count
        />
        <Editor
          v-model="state.instruction"
          :disabled="isSaving"
          :label="
            t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.LABEL')
          "
          :placeholder="
            t(
              'CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.PLACEHOLDER'
            )
          "
          :message="instructionError"
          :message-type="instructionError ? 'error' : 'info'"
          :show-character-count="false"
          enable-captain-tools
        />
      </div>
    </Dialog>
  </div>
</template>
