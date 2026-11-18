<script setup>
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useAssistantSettings } from './useAssistantSettings';
import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import AssistantAppointmentsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantAppointmentsForm.vue';

const { t } = useI18n();
const { assistant, updateAssistant } = useAssistantSettings();
const saveAppointments = async ({ inboxChanges, onSaved, ...payload }) => {
  if (!(await updateAssistant(payload))) return;
  try {
    await Promise.all(
      inboxChanges.map(change =>
        CaptainInboxesAPI.updateAppointments({
          assistantId: assistant.value.id,
          ...change,
        })
      )
    );
    onSaved();
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.APPOINTMENTS.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.SETTINGS.APPOINTMENTS.DESCRIPTION')"
  >
    <AssistantAppointmentsForm
      :assistant="assistant"
      @submit="saveAppointments"
    />
  </SettingsPageLayout>
</template>
