<script setup>
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantPaidMessagesForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantPaidMessagesForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.PAID_MESSAGES.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.SETTINGS.PAID_MESSAGES.DESCRIPTION')"
  >
    <AssistantPaidMessagesForm
      :assistant="assistant"
      @submit="updateAssistant"
    />
  </SettingsPageLayout>
</template>
