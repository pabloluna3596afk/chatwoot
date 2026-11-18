<script setup>
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantFollowupForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantFollowupForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
const { nameRich } = useAssistantName(assistant);
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.FOLLOWUP.TITLE')"
    :description="nameRich('CAPTAIN.ASSISTANTS.SETTINGS.FOLLOWUP.DESCRIPTION')"
  >
    <AssistantFollowupForm :assistant="assistant" @submit="updateAssistant" />
  </SettingsPageLayout>
</template>
