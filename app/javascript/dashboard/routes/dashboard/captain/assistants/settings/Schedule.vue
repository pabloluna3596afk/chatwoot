<script setup>
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantScheduleForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantScheduleForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
const { nameRichFrom } = useAssistantName(assistant);
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.SCHEDULE.TITLE')"
    :description="
      nameRichFrom(t('CAPTAIN.ASSISTANTS.SETTINGS.SCHEDULE.DESCRIPTION'))
    "
  >
    <AssistantScheduleForm :assistant="assistant" @submit="updateAssistant" />
  </SettingsPageLayout>
</template>
