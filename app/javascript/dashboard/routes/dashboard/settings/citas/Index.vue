<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
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
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import VerticalTabs from 'dashboard/components-next/vertical-tabs/VerticalTabs.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CalendarTemplates from './CalendarTemplates.vue';
import CalendarInvitationSettings from './CalendarInvitationSettings.vue';
import CalendarSummary from './CalendarSummary.vue';
import CalendarResources from './CalendarResources.vue';
import { useCitasPanel } from './useCitasPanel';

const { accountId, accountScopedRoute, isCloudFeatureEnabled } = useAccount();
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
  drafts,
  kit,
  attributes,
  loading,
  errors,
  load,
  previouslyConfigured,
} = useCitasPanel({
  store,
  accountId,
  captainEnabled: () => isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN),
});
const connected = computed(() => connections.value.length > 0);
const tabIds = ['resumen', 'calendarios', 'mensajes', 'invitacion'];
const tabs = computed(() =>
  tabIds.map(id => ({ id, label: t(`CITAS_PANEL.TABS.${id}`) }))
);
const activeTab = computed(() =>
  tabIds.includes(route.query.tab) ? route.query.tab : 'resumen'
);
const visited = reactive({
  invitacion: activeTab.value === 'invitacion',
  mensajes: activeTab.value === 'mensajes',
});
const dirty = reactive({ invitacion: false });
const dirtyWarning = ref(false);
const protectedTab = computed(() => dirty[activeTab.value]);
const navigate = tab => {
  if (tab === activeTab.value) return;
  if (protectedTab.value) {
    dirtyWarning.value = true;
    return;
  }
  router.push({ query: { ...route.query, tab } });
};
onBeforeRouteUpdate(to => {
  if (to.query.tab !== route.query.tab && protectedTab.value) {
    dirtyWarning.value = true;
    return false;
  }
  if (tabIds.includes(to.query.tab)) visited[to.query.tab] = true;
  dirtyWarning.value = false;
  return true;
});
onBeforeRouteLeave(() => {
  if (Object.values(dirty).some(Boolean)) {
    dirtyWarning.value = true;
    return false;
  }
  return true;
});
const updateMessages = state => {
  drafts.value = state.drafts;
  kit.value = state.kit;
};
const updateCalendar = calendar => {
  calendars.value = calendars.value.map(item =>
    item.id === calendar.id && item.connection.id === calendar.connection.id
      ? calendar
      : item
  );
};
onMounted(() => {
  if (isAdmin.value) load();
});
</script>

<template>
  <SettingsLayout class="min-w-0">
    <template #header>
      <BaseSettingsHeader
        :title="$t('SIDEBAR.CITAS')"
        :description="$t('CITAS_SETTINGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <p v-if="!isAdmin" class="text-body-main text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.ADMIN_ONLY') }}
      </p>
      <div v-else class="flex w-full min-w-0 flex-col gap-4">
        <div
          v-if="!loading.connections && !errors.connections && !connected"
          class="flex flex-wrap items-center gap-3 rounded-lg border border-n-weak p-4 text-body-main text-n-slate-11"
        >
          {{
            $t(
              previouslyConfigured
                ? 'CITAS_PANEL.DISCONNECTED'
                : 'CALENDAR_TEMPLATES.CONNECT_GOOGLE'
            )
          }}
          <RouterLink
            :to="accountScopedRoute('settings_integrations_calendars')"
            class="text-n-blue-11 underline"
          >
            {{ $t('CITAS_PANEL.RECONNECT') }}
          </RouterLink>
        </div>
        <p
          v-if="dirtyWarning"
          role="alert"
          class="text-body-main text-n-amber-11"
        >
          {{ $t('CITAS_PANEL.UNSAVED') }}
        </p>
        <div
          v-if="Object.values(errors).some(Boolean)"
          role="alert"
          class="flex flex-wrap items-center gap-2 text-body-main text-n-ruby-11"
        >
          {{ $t('CITAS_PANEL.SECTION_ERROR') }}
          <Button
            intent="secondary"
            :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
            @click="load"
          />
        </div>
        <VerticalTabs
          :model-value="activeTab"
          :tabs="tabs"
          content-class="max-w-[45rem] pb-8"
          @update:model-value="navigate"
        >
          <template #resumen>
            <CalendarSummary
              :connected="connected"
              :calendars="calendars"
              :assistants="assistants"
              :without-calendar="withoutCalendar"
              :drafts="drafts"
              :kit="kit"
              :attributes="attributes"
              :loading="loading"
              :errors="errors"
              @navigate="navigate"
            />
          </template>
          <template #calendarios>
            <Spinner
              v-if="
                loading.calendars || loading.connections || loading.assistants
              "
            />
            <CalendarResources
              v-else-if="!errors.calendars && !errors.connections"
              :calendars="calendars"
              :assistants="assistants"
              :without-calendar="withoutCalendar"
              :assistants-failed="errors.assistants"
              @updated="updateCalendar"
            />
            <RouterLink
              :to="accountScopedRoute('settings_integrations_calendars')"
              class="mt-4 text-body-main text-n-blue-11 underline"
            >
              {{ $t('CITAS_SETTINGS.MANAGE_CONNECTION') }}
            </RouterLink>
          </template>
          <template #mensajes>
            <CalendarTemplates
              v-if="visited.mensajes"
              :connected="connected"
              @updated="updateMessages"
            />
          </template>
          <template #invitacion>
            <CalendarInvitationSettings
              v-if="visited.invitacion"
              @dirty="dirty.invitacion = $event"
            />
          </template>
        </VerticalTabs>
      </div>
    </template>
  </SettingsLayout>
</template>
