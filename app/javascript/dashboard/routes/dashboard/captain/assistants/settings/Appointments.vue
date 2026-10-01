<script setup>
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantAppointmentsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantAppointmentsForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.APPOINTMENTS.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.SETTINGS.APPOINTMENTS.DESCRIPTION')"
  >
    <AssistantAppointmentsForm
      :assistant="assistant"
      @submit="updateAssistant"
    />
  </SettingsPageLayout>
</template>
