<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import TimeField from 'next/time-field/TimeField.vue';
import Button from 'next/button/Button.vue';
import {
  TIME_WINDOW_DAYS,
  buildTimeWindow,
  getTimeWindowState,
  parseTimeWindow,
  summarizeTimeWindow,
} from 'dashboard/helper/timeWindow';

const props = defineProps({
  operator: { type: String, default: 'equal_to' },
  disabled: { type: Boolean, default: false },
});
const modelValue = defineModel({ type: [String, Array], default: '' });

const { t } = useI18n();

const getModelString = value => (Array.isArray(value) ? value[0] : value);
const initial = parseTimeWindow(getModelString(modelValue.value));
const from = ref(initial?.from || '');
const to = ref(initial?.to || '');
const days = ref(initial?.days || []);
// An empty day list means every day is allowed; explicit days are a restriction.
const hasRestrictedDays = computed(() => days.value.length > 0);
const selectedDays = computed(() =>
  days.value.length ? days.value : TIME_WINDOW_DAYS
);
const state = computed(() =>
  getTimeWindowState({ from: from.value, to: to.value })
);
const composed = computed(() =>
  buildTimeWindow({ from: from.value, to: to.value, days: days.value })
);
const summary = computed(() => {
  if (state.value === 'empty') return t('AUTOMATION.TIME_WINDOW.SUMMARY_EMPTY');
  if (state.value === 'same') return t('AUTOMATION.TIME_WINDOW.ERROR_SAME');
  return summarizeTimeWindow(composed.value, t, {
    negate: props.operator === 'not_equal_to',
    withZone: true,
  });
});

// Only resync from outside when the parent really changed the value (loading a saved rule,
// switching attribute); echoing our own output back would erase half-filled fields.
watch(modelValue, value => {
  if (getModelString(value) === composed.value) return;
  const parsed = parseTimeWindow(getModelString(value));
  from.value = parsed?.from || '';
  to.value = parsed?.to || '';
  days.value = parsed?.days || [];
});

watch(composed, value => {
  if (value !== modelValue.value) modelValue.value = value;
});

const dayOptions = computed(() => [
  {
    key: 'sun',
    name: t('DAYS_OF_WEEK.SUNDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_SUN'),
  },
  {
    key: 'mon',
    name: t('DAYS_OF_WEEK.MONDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_MON'),
  },
  {
    key: 'tue',
    name: t('DAYS_OF_WEEK.TUESDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_TUE'),
  },
  {
    key: 'wed',
    name: t('DAYS_OF_WEEK.WEDNESDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_WED'),
  },
  {
    key: 'thu',
    name: t('DAYS_OF_WEEK.THURSDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_THU'),
  },
  {
    key: 'fri',
    name: t('DAYS_OF_WEEK.FRIDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_FRI'),
  },
  {
    key: 'sat',
    name: t('DAYS_OF_WEEK.SATURDAY'),
    short: t('AUTOMATION.TIME_WINDOW.DAY_SHORT_SAT'),
  },
]);

const isShortcutActive = shortcut => {
  if (shortcut === 'all') return selectedDays.value.length === 7;
  return selectedDays.value.join(',') === 'mon,tue,wed,thu,fri';
};

const toggleDay = key => {
  if (selectedDays.value.length === 1 && selectedDays.value.includes(key)) {
    return;
  }
  days.value = selectedDays.value.includes(key)
    ? selectedDays.value.filter(day => day !== key)
    : [...selectedDays.value, key];
};

const setDays = nextDays => {
  days.value = nextDays;
};
</script>

<template>
  <div
    class="flex min-w-0 flex-col gap-3 rounded-xl bg-n-alpha-2 p-3"
    :class="{ 'pointer-events-none opacity-50': disabled }"
    :aria-disabled="disabled"
  >
    <div class="grid min-w-0 grid-cols-2 gap-2">
      <div dir="ltr" class="min-w-0">
        <TimeField
          v-model="from"
          :label="t('AUTOMATION.TIME_WINDOW.FROM')"
          :disabled="disabled"
          :message-type="state === 'same' ? 'error' : 'info'"
        />
      </div>
      <div dir="ltr" class="min-w-0">
        <TimeField
          v-model="to"
          :label="t('AUTOMATION.TIME_WINDOW.TO')"
          :disabled="disabled"
          :message-type="state === 'same' ? 'error' : 'info'"
        />
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <Button
        type="button"
        variant="link"
        size="sm"
        :label="t('AUTOMATION.TIME_WINDOW.WEEKDAYS')"
        :class="
          isShortcutActive('weekdays')
            ? 'font-medium text-n-brand'
            : 'text-n-slate-11'
        "
        @click="setDays(['mon', 'tue', 'wed', 'thu', 'fri'])"
      />
      <Button
        type="button"
        variant="link"
        size="sm"
        :label="t('AUTOMATION.TIME_WINDOW.ALL')"
        :class="
          isShortcutActive('all')
            ? 'font-medium text-n-brand'
            : 'text-n-slate-11'
        "
        @click="setDays([])"
      />
    </div>

    <div
      class="grid min-w-0 grid-cols-7 gap-1"
      role="group"
      :aria-label="t('AUTOMATION.TIME_WINDOW.DAYS')"
    >
      <button
        v-for="day in dayOptions"
        :key="day.key"
        type="button"
        class="h-11 min-w-0 rounded-lg px-0.5 text-xs font-medium outline outline-1 -outline-offset-1 focus-visible:outline-2 focus-visible:outline-n-brand sm:px-1 sm:text-sm"
        :class="
          selectedDays.includes(day.key)
            ? hasRestrictedDays
              ? 'bg-n-brand text-white outline-n-brand'
              : 'bg-n-alpha-2 text-n-slate-11 outline-n-weak'
            : 'bg-n-alpha-2 text-n-slate-11 outline-n-weak hover:bg-n-alpha-3'
        "
        :aria-pressed="selectedDays.includes(day.key)"
        :aria-disabled="
          selectedDays.length === 1 && selectedDays.includes(day.key)
        "
        :aria-label="day.name"
        :title="
          selectedDays.length === 1 && selectedDays.includes(day.key)
            ? t('AUTOMATION.TIME_WINDOW.MIN_DAY')
            : day.name
        "
        @click="toggleDay(day.key)"
      >
        {{ day.short }}
      </button>
    </div>

    <p
      class="m-0 min-w-0 whitespace-normal break-words text-sm"
      :class="
        state === 'same'
          ? 'text-n-ruby-11'
          : state === 'empty'
            ? 'text-n-slate-11'
            : 'text-n-slate-12'
      "
      aria-live="polite"
    >
      {{ summary }}
    </p>
  </div>
</template>
