<script setup>
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantFollowupForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantFollowupForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.FOLLOWUP.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.SETTINGS.FOLLOWUP.DESCRIPTION')"
  >
    <AssistantFollowupForm :assistant="assistant" @submit="updateAssistant" />
  </SettingsPageLayout>
</template>
