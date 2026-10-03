<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  useApprovedTemplates,
  templateFromValue,
  templateToValue,
} from './useApprovedTemplates';
import CalendarAPI from 'dashboard/api/integrations/calendar';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import { isWhatsAppComplete } from '@chatwoot/utils';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import { useTemplateVariables } from './useTemplateVariables';

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

// Two reminders, each with its own lead time (1 to 168 hours before the appointment).
const REMINDER_KEYS = ['reminder_1', 'reminder_2'];
const REMINDER_HOURS = { min: 1, max: 168 };
const DEFAULT_REMINDERS = [
  { enabled: true, hours: 24 },
  { enabled: true, hours: 3 },
];

const initialState = {
  enabled: false,
  connectionId: '',
  calendarId: '',
  duration: 30,
  fields: [...CONTACT_FIELDS],
  minNotice: 60,
  windowDays: 14,
  reminders: DEFAULT_REMINDERS.map(reminder => ({ ...reminder })),
  templates: { confirmation: '', reminder: '', cancelled: '' },
  params: { confirmation: {}, reminder: {}, cancelled: {} },
};

const state = reactive({
  ...initialState,
  reminders: DEFAULT_REMINDERS.map(reminder => ({ ...reminder })),
  templates: { ...initialState.templates },
  params: { confirmation: {}, reminder: {}, cancelled: {} },
});
const { templateOptions, templateEntry } = useApprovedTemplates();
const { variableOptions, previewValues } = useTemplateVariables({
  appointment: true,
});

// The one "paid templates" switch of the assistant lives in its own page; the pickers only matter once it is on.
const paidEnabled = computed(
  () => props.assistant?.config?.allow_paid_templates === true
);
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
    reminders: REMINDER_KEYS.map((key, index) => ({
      enabled: settings[key]?.enabled !== false,
      hours: settings[key]?.hours_before ?? DEFAULT_REMINDERS[index].hours,
    })),
    templates: {
      confirmation: templateToValue(settings.template_confirmation),
      reminder: templateToValue(settings.template_reminder),
      cancelled: templateToValue(settings.template_cancelled),
    },
    params: {
      confirmation: settings.template_confirmation?.processed_params || {},
      reminder: settings.template_reminder?.processed_params || {},
      cancelled: settings.template_cancelled?.processed_params || {},
    },
  });
};

const hoursValid = hours =>
  Number.isInteger(Number(hours)) &&
  Number(hours) >= REMINDER_HOURS.min &&
  Number(hours) <= REMINDER_HOURS.max;

const hoursError = index =>
  showErrors.value && !hoursValid(state.reminders[index].hours)
    ? t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.HOURS_ERROR')
    : '';

// A template with a variable left empty cannot be saved.
const templateComplete = key =>
  !state.templates[key] ||
  !templateEntry(state.templates[key]) ||
  isWhatsAppComplete(templateEntry(state.templates[key]), state.params[key]);

const selectTemplate = (key, value) => {
  state.templates[key] = value;
  state.params[key] = {};
};

const reminderPayload = reminder => ({
  enabled: reminder.enabled,
  hours_before: Number(reminder.hours),
});

const handleSubmit = () => {
  showErrors.value = true;
  if (state.enabled && (!state.connectionId || !state.calendarId)) return;
  if (!state.reminders.every(reminder => hoursValid(reminder.hours))) return;
  if (!TEMPLATE_KEYS.every(templateComplete)) return;

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
        reminder_1: reminderPayload(state.reminders[0]),
        reminder_2: reminderPayload(state.reminders[1]),
        template_confirmation: templateFromValue(
          state.templates.confirmation,
          state.params.confirmation
        ),
        template_reminder: templateFromValue(
          state.templates.reminder,
          state.params.reminder
        ),
        template_cancelled: templateFromValue(
          state.templates.cancelled,
          state.params.cancelled
        ),
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
            <p
              data-testid="appointments-confirmation-note"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{
                t(
                  'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.CONFIRMATION_NOTE'
                )
              }}
            </p>
            <div
              v-for="(reminder, index) in state.reminders"
              :key="REMINDER_KEYS[index]"
              class="flex flex-col gap-1"
            >
              <div
                class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
              >
                <Checkbox
                  :data-testid="`appointments-reminder-${index + 1}`"
                  :model-value="reminder.enabled"
                  @update:model-value="reminder.enabled = $event"
                />
                <span>
                  {{
                    t(
                      'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.REMINDER_LABEL',
                      { number: index + 1 }
                    )
                  }}
                </span>
                <Input
                  v-model="reminder.hours"
                  type="number"
                  size="sm"
                  :min="String(REMINDER_HOURS.min)"
                  :max="String(REMINDER_HOURS.max)"
                  :disabled="!reminder.enabled"
                  :data-testid="`appointments-reminder-${index + 1}-hours`"
                  :message="hoursError(index)"
                  message-type="error"
                  class="w-24"
                />
                <span>
                  {{
                    t(
                      'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.HOURS_BEFORE'
                    )
                  }}
                </span>
              </div>
              <p
                :data-testid="`appointments-reminder-${index + 1}-hint`"
                class="mb-0 text-xs text-n-slate-11"
              >
                {{
                  t(
                    'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.WINDOW_HINT'
                  )
                }}
              </p>
            </div>
            <p
              v-if="!paidEnabled"
              data-testid="appointments-paid-hint"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{
                t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.PAID_HINT')
              }}
            </p>
            <div
              v-if="paidEnabled"
              data-testid="appointments-templates"
              class="flex flex-col gap-4"
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
                  :model-value="state.templates[key]"
                  :data-testid="`appointments-template-${key}`"
                  full-width
                  :options="templateOptions(state.templates[key])"
                  @update:model-value="selectTemplate(key, $event)"
                />
                <WhatsAppTemplateParser
                  v-if="
                    state.templates[key] && templateEntry(state.templates[key])
                  "
                  :key="state.templates[key]"
                  :template="templateEntry(state.templates[key])"
                  :model-value="state.params[key]"
                  :variable-options="variableOptions"
                  :preview-values="previewValues"
                  @update:model-value="state.params[key] = $event"
                />
                <p
                  v-if="showErrors && !templateComplete(key)"
                  :data-testid="`appointments-template-${key}-error`"
                  class="mb-0 text-xs text-n-ruby-9"
                >
                  {{ t('CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.ERROR') }}
                </p>
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
