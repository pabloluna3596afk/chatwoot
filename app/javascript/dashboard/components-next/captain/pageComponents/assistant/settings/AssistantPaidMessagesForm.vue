<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const allowPaidTemplates = ref(false);

watch(
  () => props.assistant,
  assistant => {
    if (!assistant) return;
    allowPaidTemplates.value = assistant.config?.allow_paid_templates === true;
  },
  { immediate: true }
);

const handleSubmit = () => {
  emit('submit', {
    config: {
      ...props.assistant.config,
      allow_paid_templates: allowPaidTemplates.value,
    },
  });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <SettingsToggleSection
      v-model="allowPaidTemplates"
      :header="t('CAPTAIN.ASSISTANTS.FORM.PAID_MESSAGES.TOGGLE')"
      :description="t('CAPTAIN.ASSISTANTS.FORM.PAID_MESSAGES.TOGGLE_HELP')"
    />
    <p data-testid="paid-messages-note" class="mb-0 text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.PAID_MESSAGES.NOTE') }}
    </p>
    <div>
      <Button
        data-testid="paid-messages-save"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
