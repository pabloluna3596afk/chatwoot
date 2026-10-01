<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import CalendarAPI from 'dashboard/api/integrations/calendar';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t, locale } = useI18n();
const { accountScopedRoute } = useAccount();

const CONTACT_FIELDS = ['name', 'phone', 'email'];
const DURATION_OPTIONS = [15, 30, 45, 60, 90, 120];
const NOTICE_OPTIONS = [0, 30, 60, 120, 240, 1440];
const WINDOW_OPTIONS = [7, 14, 30, 60, 90];
const TEMPLATE_KEYS = ['confirmation', 'reminder', 'cancelled'];

const REMINDER_OPTIONS = [
  {
    key: 'sendConfirmation',
    testId: 'send-confirmation',
    label: 'CONFIRMATION',
  },
  { key: 'reminder24h', testId: 'reminder-24h', label: 'REMINDER_24H' },
  { key: 'reminder2h', testId: 'reminder-2h', label: 'REMINDER_2H' },
];

const initialState = {
  enabled: false,
  connectionId: '',
  calendarId: '',
  duration: 30,
  fields: [...CONTACT_FIELDS],
  minNotice: 60,
  windowDays: 14,
  sendConfirmation: true,
  reminder24h: true,
  reminder2h: true,
  allowPaidTemplates: false,
  templates: { confirmation: '', reminder: '', cancelled: '' },
};

const state = reactive({
  ...initialState,
  templates: { ...initialState.templates },
});
const inboxes = useMapGetter('inboxes/getInboxes');
const connections = ref([]);
const calendars = ref([]);
const isLoading = ref(true);
const loadFailed = ref(false);
const showErrors = ref(false);

const hasConnections = computed(() => connections.value.length > 0);

const connectionOptions = computed(() => [
  {
    value: '',
    label: t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CONNECTION_PLACEHOLDER'),
  },
  ...connections.value.map(connection => ({
    value: connection.id,
    label: connection.name
      ? `${connection.name} (${connection.email})`
      : connection.email,
  })),
]);

const calendarOptions = computed(() => [
  {
    value: '',
    label: t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CALENDAR_PLACEHOLDER'),
  },
  ...calendars.value.map(calendar => ({
    value: calendar.id,
    label: calendar.summary,
  })),
]);

const selectedCalendar = computed(() =>
  calendars.value.find(calendar => calendar.id === state.calendarId)
);

const formatHour = hour => `${String(hour).padStart(2, '0')}:00`;

// Monday first; the values are Date#wday (0 = Sunday), like the backend working_days.
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0];

// 2030-01-13 is a Sunday, so adding the weekday number lands on that weekday.
const weekdayLabel = day =>
  new Intl.DateTimeFormat(locale.value, { weekday: 'short' }).format(
    new Date(2030, 0, 13 + day)
  );

const daysText = calendar => {
  const days = calendar.working_days ?? DAY_ORDER;
  if (days.length === DAY_ORDER.length) {
    return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.EVERY_DAY');
  }
  return DAY_ORDER.filter(day => days.includes(day))
    .map(weekdayLabel)
    .join(', ');
};

const hoursHint = computed(() => {
  if (!selectedCalendar.value) return '';
  return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.HOURS_HINT', {
    start: formatHour(selectedCalendar.value.hour_start ?? 8),
    end: formatHour(selectedCalendar.value.hour_end ?? 20),
    days: daysText(selectedCalendar.value),
  });
});

const minutesLabel = minutes => {
  if (minutes === 0) return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.NO_NOTICE');
  if (minutes % 1440 === 0) {
    return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.DAYS', {
      count: minutes / 1440,
    });
  }
  if (minutes % 60 === 0) {
    return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.HOURS', {
      count: minutes / 60,
    });
  }
  return t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.MINUTES', {
    count: minutes,
  });
};

const withCurrent = (options, current) =>
  options.includes(current)
    ? options
    : [...options, current].sort((a, b) => a - b);

const durationOptions = computed(() =>
  withCurrent(DURATION_OPTIONS, state.duration).map(value => ({
    value,
    label: minutesLabel(value),
  }))
);

const noticeOptions = computed(() =>
  withCurrent(NOTICE_OPTIONS, state.minNotice).map(value => ({
    value,
    label: minutesLabel(value),
  }))
);

const windowOptions = computed(() =>
  withCurrent(WINDOW_OPTIONS, state.windowDays).map(value => ({
    value,
    label: t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.DAYS', { count: value }),
  }))
);

// Approved WhatsApp templates of the account's inboxes, as "name|language".
const templateKey = template => `${template.name}|${template.language}`;

const approvedTemplates = computed(() => {
  const seen = new Map();
  (inboxes.value || [])
    .filter(inbox => inbox.channel_type === 'Channel::Whatsapp')
    .forEach(inbox => {
      (inbox.message_templates || [])
        .filter(
          template => String(template.status).toLowerCase() === 'approved'
        )
        .forEach(template => {
          const key = templateKey(template);
          if (!seen.has(key)) {
            seen.set(key, {
              value: key,
              label: `${template.name} (${template.language})`,
            });
          }
        });
    });
  return [...seen.values()];
});

const templateOptions = key => {
  const current = state.templates[key];
  const known = approvedTemplates.value.some(item => item.value === current);
  const options =
    current && !known
      ? [
          ...approvedTemplates.value,
          { value: current, label: current.replace('|', ' (') + ')' },
        ]
      : approvedTemplates.value;
  return [
    {
      value: '',
      label: t(
        'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.TEMPLATE_PLACEHOLDER'
      ),
    },
    ...options,
  ];
};

const templateFromValue = value => {
  if (!value) return null;
  const [name, language] = value.split('|');
  return { name, language };
};

const templateToValue = template =>
  template?.name && template?.language ? templateKey(template) : '';

const connectionError = computed(() =>
  showErrors.value && state.enabled && !state.connectionId
    ? t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.ERRORS.CONNECTION')
    : ''
);

const calendarError = computed(() =>
  showErrors.value && state.enabled && !state.calendarId
    ? t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.ERRORS.CALENDAR')
    : ''
);

const toggleField = (field, checked) => {
  const without = state.fields.filter(item => item !== field);
  state.fields = checked
    ? CONTACT_FIELDS.filter(item => item === field || without.includes(item))
    : without;
};

const loadCalendars = async connectionId => {
  calendars.value = [];
  if (!connectionId) return;
  try {
    const { data } = await CalendarAPI.getCalendars(connectionId);
    calendars.value = data.payload || [];
  } catch {
    calendars.value = [];
  }
};

const handleConnectionChange = async connectionId => {
  state.calendarId = '';
  await loadCalendars(connectionId);
};

const updateStateFromAssistant = assistant => {
  const settings = assistant?.config?.appointments || {};
  Object.assign(state, {
    enabled: settings.enabled === true,
    connectionId: settings.calendar_connection_id ?? '',
    calendarId: settings.calendar_id ?? '',
    duration: settings.slot_duration_minutes ?? initialState.duration,
    fields: Array.isArray(settings.required_contact_fields)
      ? [...settings.required_contact_fields]
      : [...initialState.fields],
    minNotice: settings.min_notice_minutes ?? initialState.minNotice,
    windowDays: settings.booking_window_days ?? initialState.windowDays,
    sendConfirmation: settings.send_confirmation !== false,
    reminder24h: settings.reminder_24h !== false,
    reminder2h: settings.reminder_2h !== false,
    allowPaidTemplates: settings.allow_paid_templates === true,
    templates: {
      confirmation: templateToValue(settings.template_confirmation),
      reminder: templateToValue(settings.template_reminder),
      cancelled: templateToValue(settings.template_cancelled),
    },
  });
};

const handleSubmit = () => {
  showErrors.value = true;
  if (state.enabled && (!state.connectionId || !state.calendarId)) return;

  emit('submit', {
    config: {
      ...props.assistant.config,
      appointments: {
        enabled: state.enabled,
        calendar_connection_id: state.connectionId || null,
        calendar_id: state.calendarId || null,
        slot_duration_minutes: Number(state.duration),
        required_contact_fields: [...state.fields],
        min_notice_minutes: Number(state.minNotice),
        booking_window_days: Number(state.windowDays),
        send_confirmation: state.sendConfirmation,
        reminder_24h: state.reminder24h,
        reminder_2h: state.reminder2h,
        allow_paid_templates: state.allowPaidTemplates,
        template_confirmation: templateFromValue(state.templates.confirmation),
        template_reminder: templateFromValue(state.templates.reminder),
        template_cancelled: templateFromValue(state.templates.cancelled),
      },
    },
  });
};

const loadConnections = async () => {
  try {
    const { data } = await CalendarAPI.getConnections();
    connections.value = data.payload || [];
  } catch {
    loadFailed.value = true;
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => props.assistant,
  async newAssistant => {
    if (!newAssistant) return;
    updateStateFromAssistant(newAssistant);
    await loadCalendars(state.connectionId);
  },
  { immediate: true }
);

onMounted(loadConnections);
</script>

<template>
  <div class="flex flex-col gap-4">
    <p v-if="isLoading" class="mb-0 text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.LOADING') }}
    </p>
    <p v-else-if="loadFailed" class="mb-0 text-sm text-n-ruby-9">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.LOAD_ERROR') }}
    </p>
    <div
      v-else-if="!hasConnections"
      data-testid="appointments-no-calendar"
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    >
      <span class="text-sm text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.NO_CALENDAR') }}
      </span>
      <router-link
        :to="accountScopedRoute('settings_integrations_calendars')"
        class="w-fit text-sm font-medium text-n-brand hover:underline"
      >
        {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CONNECT_CALENDAR') }}
      </router-link>
    </div>
    <template v-else>
      <SettingsToggleSection
        v-model="state.enabled"
        :header="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.TOGGLE')"
        :description="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.TOGGLE_HELP')"
      >
        <div
          v-if="state.enabled"
          data-testid="appointments-fields"
          class="flex w-full flex-col gap-5 border-t border-n-weak px-4 pb-2 pt-4"
        >
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CONNECTION') }}
            </label>
            <Select
              v-model="state.connectionId"
              data-testid="appointments-connection"
              full-width
              :options="connectionOptions"
              :error="connectionError"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CONNECTION')"
              @update:model-value="handleConnectionChange"
            />
            <p v-if="connectionError" class="mb-0 text-xs text-n-ruby-9">
              {{ connectionError }}
            </p>
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CALENDAR') }}
            </label>
            <Select
              v-model="state.calendarId"
              data-testid="appointments-calendar"
              full-width
              :disabled="!state.connectionId"
              :options="calendarOptions"
              :error="calendarError"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.CALENDAR')"
            />
            <p v-if="calendarError" class="mb-0 text-xs text-n-ruby-9">
              {{ calendarError }}
            </p>
            <p
              v-if="hoursHint"
              data-testid="appointments-hours-hint"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{ hoursHint }}
            </p>
          </div>

          <div class="grid gap-4 sm:grid-cols-3">
            <div class="flex flex-col gap-1">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.DURATION') }}
              </label>
              <Select
                v-model.number="state.duration"
                data-testid="appointments-duration"
                full-width
                :options="durationOptions"
                :aria-label="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.DURATION')"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.NOTICE') }}
              </label>
              <Select
                v-model.number="state.minNotice"
                data-testid="appointments-notice"
                full-width
                :options="noticeOptions"
                :aria-label="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.NOTICE')"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.WINDOW') }}
              </label>
              <Select
                v-model.number="state.windowDays"
                data-testid="appointments-window"
                full-width
                :options="windowOptions"
                :aria-label="t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.WINDOW')"
              />
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REQUIRED_FIELDS') }}
            </span>
            <label
              v-for="field in CONTACT_FIELDS"
              :key="field"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <Checkbox
                :data-testid="`appointments-field-${field}`"
                :model-value="state.fields.includes(field)"
                @update:model-value="toggleField(field, $event)"
              />
              {{
                t(
                  `CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.FIELDS.${field.toUpperCase()}`
                )
              }}
            </label>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.FIELDS_HINT') }}
            </p>
          </div>

          <div class="flex flex-col gap-2" data-testid="appointments-reminders">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.TITLE') }}
            </span>
            <label
              v-for="option in REMINDER_OPTIONS"
              :key="option.key"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <Checkbox
                :data-testid="`appointments-${option.testId}`"
                :model-value="state[option.key]"
                @update:model-value="state[option.key] = $event"
              />
              {{
                t(
                  `CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.${option.label}`
                )
              }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <Checkbox
                data-testid="appointments-paid-templates"
                :model-value="state.allowPaidTemplates"
                @update:model-value="state.allowPaidTemplates = $event"
              />
              {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.PAID') }}
            </label>
            <p
              data-testid="appointments-paid-note"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{
                t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.PAID_NOTE')
              }}
            </p>
            <div
              v-if="state.allowPaidTemplates"
              data-testid="appointments-templates"
              class="grid gap-4 sm:grid-cols-3"
            >
              <div
                v-for="key in TEMPLATE_KEYS"
                :key="key"
                class="flex flex-col gap-1"
              >
                <label class="text-sm font-medium text-n-slate-12">
                  {{
                    t(
                      `CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.TEMPLATE_${key.toUpperCase()}`
                    )
                  }}
                </label>
                <Select
                  v-model="state.templates[key]"
                  :data-testid="`appointments-template-${key}`"
                  full-width
                  :options="templateOptions(key)"
                />
              </div>
            </div>
          </div>
        </div>
      </SettingsToggleSection>
      <div>
        <Button
          data-testid="appointments-save"
          :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
          @click="handleSubmit"
        />
      </div>
    </template>
  </div>
</template>
