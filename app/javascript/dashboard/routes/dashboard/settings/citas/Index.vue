<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import {
  onBeforeRouteLeave,
  onBeforeRouteUpdate,
  useRoute,
  useRouter,
} from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CitasStepCalendar from './CitasStepCalendar.vue';
import CitasStepMessages from './CitasStepMessages.vue';
import CitasStepInvitation from './CitasStepInvitation.vue';
import CitasContactData from './CitasContactData.vue';
import { useCitasPanel } from './useCitasPanel';

const { accountId, isCloudFeatureEnabled } = useAccount();
const { isAdmin } = useAdmin();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const {
  connections,
  calendars,
  assistants,
  withoutCalendar,
  attributes,
  templateState,
  templateData,
  loading,
  errors,
  loadConnections,
  loadCalendars,
  loadCalendar,
  loadAssistants,
  loadAttributes,
  loadTemplateState,
  calendarErrors,
  calendarLoading,
} = useCitasPanel({
  store,
  accountId,
  captainEnabled: () => isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN),
});
const connected = computed(() => connections.value.length > 0);
const expandedStep = ref('');
const dirty = reactive({ invitation: false });
const dirtyWarning = ref(false);
const connectionsReady = ref(false);
let resourcesRequested = false;

const routeTab = computed(() => {
  const tabs = {
    calendarios: 'calendar',
    mensajes: 'messages',
    invitacion: 'invitation',
  };
  return tabs[route.query.tab] || '';
});
watch(
  routeTab,
  async tab => {
    if (tab) expandedStep.value = tab;
    if (route.query.tab !== undefined) {
      const query = { ...route.query };
      delete query.tab;
      await router.replace({ query });
    }
  },
  { immediate: true }
);
const toggleStep = step => {
  if (dirty.invitation && expandedStep.value !== step) {
    dirtyWarning.value = true;
    return;
  }
  expandedStep.value = expandedStep.value === step ? '' : step;
  dirtyWarning.value = false;
};
onBeforeRouteLeave(() => {
  if (dirty.invitation) {
    dirtyWarning.value = true;
    return false;
  }
  return true;
});
onBeforeRouteUpdate((to, from) => {
  if (dirty.invitation && to.fullPath !== from.fullPath) {
    dirtyWarning.value = true;
    return false;
  }
  return true;
});
const retryConnections = async () => {
  await loadConnections();
  connectionsReady.value = !errors.connections;
};
watch([connected, connectionsReady], ([isConnected, ready]) => {
  if (isAdmin.value && isConnected && ready && !resourcesRequested) {
    resourcesRequested = true;
    loadCalendars();
    loadAssistants();
  }
});
const updateCalendar = calendar => {
  calendars.value = calendars.value.map(item =>
    item.id === calendar.id && item.connection.id === calendar.connection.id
      ? calendar
      : item
  );
};
onMounted(async () => {
  if (!isAdmin.value) return;
  await retryConnections();
  loadAttributes();
  loadTemplateState();
});
const refreshTemplates = () => loadTemplateState();
const description = t('CITAS_SCREEN.DESCRIPTION');
</script>

<template>
  <SettingsLayout class="min-w-0">
    <template #header>
      <BaseSettingsHeader
        :title="$t('SIDEBAR.CITAS')"
        :description="description"
      />
    </template>
    <template #body>
      <p v-if="!isAdmin" class="text-body-main text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.ADMIN_ONLY') }}
      </p>
      <div v-else class="w-full min-w-0 max-w-[58rem] pb-8">
        <p
          v-if="dirtyWarning"
          role="alert"
          class="text-body-main text-n-amber-11"
        >
          {{ $t('CITAS_PANEL.UNSAVED') }}
        </p>
        <CitasStepCalendar
          :connections="connections"
          :calendars="calendars"
          :connected="connected"
          :loading="loading"
          :errors="errors"
          :expanded="expandedStep === 'calendar'"
          :calendar-errors="calendarErrors"
          :calendar-loading="calendarLoading"
          :assistants="assistants"
          :without-calendar="withoutCalendar"
          @toggle="toggleStep('calendar')"
          @retry-connections="retryConnections"
          @retry-calendar="loadCalendar"
          @retry-assistants="loadAssistants"
          @updated="updateCalendar"
        />
        <CitasStepMessages
          :connected="connected"
          :disabled="!connected"
          :expanded="expandedStep === 'messages'"
          :template-data="templateData"
          :template-state="templateState"
          :loading="loading.templates"
          :error="errors.templates"
          :refresh="refreshTemplates"
          @toggle="toggleStep('messages')"
        />
        <CitasStepInvitation
          :disabled="!connected"
          :expanded="expandedStep === 'invitation'"
          @toggle="toggleStep('invitation')"
          @dirty="dirty.invitation = $event"
        />
        <CitasContactData
          :attributes="attributes"
          :loading="loading.attributes"
          :error="errors.attributes"
          :expanded="expandedStep === 'contact'"
          @toggle="toggleStep('contact')"
          @retry="loadAttributes"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
