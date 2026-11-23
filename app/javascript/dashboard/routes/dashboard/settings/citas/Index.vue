<script setup>
import { computed, onMounted, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CalendarTemplates from './CalendarTemplates.vue';
import CalendarAppointmentAttributes from './CalendarAppointmentAttributes.vue';
import CalendarInvitationSettings from './CalendarInvitationSettings.vue';

const { accountId, accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();
const store = useStore();
const hasGoogleConnection = useMapGetter(
  'calendarConnections/hasGoogleConnection'
);
const connected = computed(() => hasGoogleConnection.value(accountId.value));
const loading = ref(true);
const loadFailed = ref(false);
const load = async () => {
  if (!isAdmin.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  loadFailed.value = false;
  try {
    await store.dispatch('calendarConnections/get', accountId.value);
  } catch {
    loadFailed.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" class="min-w-0">
    <template #header>
      <BaseSettingsHeader
        :title="$t('SIDEBAR.CITAS')"
        :description="$t('CITAS_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <div class="flex w-full min-w-0 max-w-3xl flex-col gap-4">
        <p v-if="!isAdmin" class="text-body-main text-n-slate-11">
          {{ $t('CALENDAR_TEMPLATES.ADMIN_ONLY') }}
        </p>
        <div
          v-else-if="loadFailed"
          role="alert"
          class="flex flex-wrap items-center gap-2 text-body-main text-n-ruby-11"
        >
          {{ $t('INTEGRATION_SETTINGS.CALENDARS.LOAD_ERROR') }}
          <Button
            intent="secondary"
            :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
            @click="load"
          />
        </div>
        <template v-else>
          <RouterLink
            :to="accountScopedRoute('settings_integrations_calendars')"
            class="self-start text-body-main text-n-blue-11 underline"
          >
            {{ $t('CITAS_SETTINGS.MANAGE_CONNECTION') }}
          </RouterLink>
          <template v-if="connected">
            <CalendarTemplates :connected="connected" />
            <CalendarAppointmentAttributes />
            <CalendarInvitationSettings />
          </template>
          <p v-else class="text-body-main text-n-slate-11">
            {{ $t('CALENDAR_TEMPLATES.CONNECT_GOOGLE') }}
          </p>
        </template>
      </div>
    </template>
  </SettingsLayout>
</template>
