<script setup>
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantMessagingForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantMessagingForm.vue';
import AccountAPI from 'dashboard/api/account';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
const saveMessaging = async ({ assistantPayload, dailyCap }) => {
  const saved = await updateAssistant(assistantPayload);
  if (!saved) return;
  try {
    await AccountAPI.update('', { captain_template_daily_cap: dailyCap });
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.SAVE_ERROR'));
  }
};
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.MESSAGING.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.SETTINGS.MESSAGING.DESCRIPTION')"
  >
    <AssistantMessagingForm :assistant="assistant" @submit="saveMessaging" />
  </SettingsPageLayout>
</template>
