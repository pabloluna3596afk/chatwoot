<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAccount } from 'dashboard/composables/useAccount';

const props = defineProps({
  connected: Boolean,
  calendars: { type: Array, required: true },
  assistants: { type: Array, required: true },
  withoutCalendar: { type: Array, required: true },
  drafts: { type: Object, default: null },
  kit: { type: Object, default: null },
  loading: { type: Object, required: true },
  errors: { type: Object, required: true },
});
const emit = defineEmits(['navigate']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const summary = computed(() => {
  const destinations = Object.values(props.drafts?.results || {}).flatMap(
    result => result.destinations || []
  );
  const counts = {
    ready: destinations.filter(item => item.state === 'usable').length,
    unlinked: destinations.filter(
      item => item.reason === 'explicit_link_required'
    ).length,
    review: destinations.filter(item => item.state === 'pending_approval')
      .length,
    pending: destinations.filter(
      item =>
        !['usable', 'pending_approval'].includes(item.state) &&
        item.reason !== 'explicit_link_required'
    ).length,
  };
  return Object.entries(counts)
    .filter(([, count]) => count > 0)
    .map(([state, count]) => t(`CITAS_PANEL.TEMPLATE_COUNTS.${state}`, count))
    .join(' · ');
});
const reminderReady = computed(() =>
  props.drafts?.results?.reminder?.destinations?.some(
    item => item.state === 'usable'
  )
);
const reminderReason = computed(() => {
  if (!props.connected) return t('CITAS_PANEL.DISCONNECTED');
  return t(
    reminderReady.value
      ? 'CITAS_PANEL.REMINDER_READY'
      : 'CALENDAR_TEMPLATES.REMINDER_LOCKED'
  );
});
const rows = computed(() => [
  {
    key: 'calendars',
    waiting: props.loading.connections,
    unavailable: props.errors.calendars || props.errors.connections,
    title: t('CITAS_PANEL.TABS.calendarios'),
    text: props.calendars.length
      ? t('CITAS_PANEL.CALENDAR_COUNT', { count: props.calendars.length })
      : t('CITAS_PANEL.NO_CALENDARS'),
    tab: 'calendarios',
  },
  {
    key: 'assistants',
    waiting: props.loading.calendars || props.loading.connections,
    unavailable:
      props.errors.calendars ||
      props.errors.connections ||
      props.errors.assistants,
    title: t('CITAS_PANEL.ASSISTANTS'),
    text: props.assistants.length
      ? t('CITAS_PANEL.ASSISTANT_COUNT', {
          count: props.assistants.length - props.withoutCalendar.length,
          missing: props.withoutCalendar.length,
        })
      : t('CITAS_PANEL.NO_ASSISTANTS'),
    tab: 'calendarios',
  },
  {
    key: 'messages',
    title: t('CALENDAR_TEMPLATES.TITLE'),
    text: Object.values(props.drafts?.results || {}).some(
      item => item.draft_exists || item.destinations?.length
    )
      ? summary.value
      : t('CALENDAR_TEMPLATES.NOT_PREPARED'),
    tab: 'mensajes',
  },
  {
    key: 'messages',
    title: t('CALENDAR_TEMPLATES.REMINDER_TOGGLE'),
    text:
      t(
        props.kit?.reminder_enabled
          ? 'CITAS_PANEL.REMINDER_ON'
          : 'CITAS_PANEL.REMINDER_OFF'
      ) +
      ' ' +
      reminderReason.value,
    tab: 'mensajes',
  },
]);
</script>

<template>
  <section
    class="divide-y divide-n-weak rounded-xl border border-n-weak bg-n-card px-4"
  >
    <div class="flex flex-wrap items-center justify-between gap-3 py-4">
      <div class="min-w-0">
        <h3 class="text-body-main font-medium text-n-slate-12">
          {{ $t('INTEGRATION_SETTINGS.CALENDARS.GOOGLE') }}
        </h3>
        <Spinner v-if="loading.connections" />
        <p v-else role="status" class="text-body-main text-n-slate-11">
          {{
            $t(
              errors.connections
                ? 'INTEGRATION_SETTINGS.CALENDARS.LOAD_ERROR'
                : connected
                  ? 'CITAS_PANEL.CONNECTED'
                  : 'CALENDAR_TEMPLATES.CONNECT_GOOGLE'
            )
          }}
        </p>
      </div>
      <RouterLink
        :to="accountScopedRoute('settings_integrations_calendars')"
        class="text-body-main text-n-blue-11 underline"
      >
        {{ $t('CITAS_SETTINGS.MANAGE_CONNECTION') }}
      </RouterLink>
    </div>
    <div
      v-for="(row, index) in rows"
      :key="index"
      class="flex flex-wrap items-center justify-between gap-3 py-4"
    >
      <div class="min-w-0 flex-1">
        <h3 class="text-body-main font-medium text-n-slate-12">
          {{ row.title }}
        </h3>
        <Spinner v-if="loading[row.key] || row.waiting" />
        <p v-else role="status" class="text-body-main text-n-slate-11">
          {{
            row.unavailable || errors[row.key]
              ? $t('CITAS_PANEL.SECTION_ERROR')
              : row.text
          }}
        </p>
      </div>
      <Button
        intent="secondary"
        :label="
          $t('CITAS_PANEL.VIEW', { section: $t(`CITAS_PANEL.TABS.${row.tab}`) })
        "
        @click="emit('navigate', row.tab)"
      />
    </div>
  </section>
</template>
