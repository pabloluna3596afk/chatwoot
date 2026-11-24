<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({ calendar: { type: Object, required: true } });
const emit = defineEmits(['updated']);
const { t, locale } = useI18n();
const saving = ref(false);
const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0];
const hours = Array.from({ length: 24 }, (_, hour) => ({
  value: hour,
  label: `${String(hour).padStart(2, '0')}:00`,
}));
const endHours = computed(() =>
  hours.filter(hour => hour.value > (props.calendar.hour_start ?? 8))
);
const weekdayLabel = day =>
  new Intl.DateTimeFormat(locale.value, { weekday: 'short' }).format(
    new Date(2030, 0, 13 + day)
  );
const save = async changes => {
  saving.value = true;
  const calendar = { ...props.calendar, ...changes };
  try {
    const { data } = await CalendarAPI.updateCalendars(calendar.connection.id, [
      {
        external_id: calendar.id,
        summary: calendar.summary,
        is_enabled: calendar.enabled,
        hour_start: calendar.hour_start ?? 8,
        hour_end: calendar.hour_end ?? 20,
        working_days: calendar.working_days ?? ALL_DAYS,
      },
    ]);
    emit('updated', {
      ...data.payload.find(item => item.id === calendar.id),
      connection: calendar.connection,
    });
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        t('INTEGRATION_SETTINGS.CALENDARS.SAVE_ERROR')
    );
  } finally {
    saving.value = false;
  }
};
const updateStart = hour =>
  save({
    hour_start: hour,
    hour_end: Math.max(props.calendar.hour_end ?? 20, hour + 1),
  });
const toggleDay = day => {
  const days = props.calendar.working_days ?? ALL_DAYS;
  const next = days.includes(day)
    ? days.filter(value => value !== day)
    : [...days, day].sort((a, b) => a - b);
  if (next.length) save({ working_days: next });
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-3">
    <p class="text-body-main font-medium text-n-slate-12">
      {{ $t('INTEGRATION_SETTINGS.CALENDARS.HOURS') }}
    </p>
    <div class="grid w-full max-w-xs grid-cols-1 gap-3 sm:grid-cols-2">
      <ComboBox
        :model-value="calendar.hour_start ?? 8"
        :options="hours.filter(hour => hour.value < 23)"
        :allow-deselect="false"
        :disabled="saving"
        :label="$t('CITAS_PANEL.START')"
        :aria-label="$t('CITAS_PANEL.START')"
        @update:model-value="updateStart"
      />
      <ComboBox
        :model-value="calendar.hour_end ?? 20"
        :options="endHours"
        :allow-deselect="false"
        :disabled="saving"
        :label="$t('CITAS_PANEL.END')"
        :aria-label="$t('CITAS_PANEL.END')"
        @update:model-value="save({ hour_end: $event })"
      />
    </div>
    <div
      class="flex flex-wrap gap-3"
      role="group"
      :aria-label="$t('INTEGRATION_SETTINGS.CALENDARS.DAYS')"
    >
      <label
        v-for="day in DAY_ORDER"
        :key="day"
        class="flex items-center gap-1 text-body-main text-n-slate-11"
      >
        <Checkbox
          :model-value="(calendar.working_days ?? ALL_DAYS).includes(day)"
          :disabled="saving"
          :data-testid="`calendar-day-${day}`"
          @update:model-value="toggleDay(day)"
        />
        {{ weekdayLabel(day) }}
      </label>
    </div>
  </div>
</template>
