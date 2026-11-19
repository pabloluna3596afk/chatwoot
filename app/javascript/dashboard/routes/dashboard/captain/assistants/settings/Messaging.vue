<script setup>
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantMessagingForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantMessagingForm.vue';

const { t } = useI18n();
const { assistant } = useAssistantSettings();
const { nameRich } = useAssistantName(assistant);
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.MESSAGING.TITLE')"
    :description="nameRich('CAPTAIN.ASSISTANTS.SETTINGS.MESSAGING.DESCRIPTION')"
  >
    <AssistantMessagingForm :assistant="assistant" />
  </SettingsPageLayout>
</template>
