<script setup>
import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DocumentForm from './DocumentForm.vue';

defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'createSuccess']);
const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const saveError = ref('');

const i18nKey = 'CAPTAIN.DOCUMENTS.CREATE';

const handleSubmit = async newDocument => {
  saveError.value = '';
  try {
    await store.dispatch('captainDocuments/create', newDocument);
    emit('createSuccess');
    useAlert(t(`${i18nKey}.SUCCESS_MESSAGE`));
    dialogRef.value.close();
  } catch (error) {
    const errorMessage = error.message || t(`${i18nKey}.ERROR_MESSAGE`);
    saveError.value = errorMessage;
    useAlert(errorMessage);
  }
};

const handleClose = () => {
  emit('close');
};

const handleCancel = () => {
  dialogRef.value.close();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="$t(`${i18nKey}.TITLE`)"
    :description="$t('CAPTAIN.DOCUMENTS.FORM_DESCRIPTION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <p v-if="saveError" role="alert" class="text-sm text-n-ruby-11">
      {{ saveError }}
    </p>
    <DocumentForm
      :assistant-id="assistantId"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
    <template #footer />
  </Dialog>
</template>
