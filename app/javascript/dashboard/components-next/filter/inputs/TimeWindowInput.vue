<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import TimeField from 'next/time-field/TimeField.vue';
import {
  TIME_WINDOW_DAYS,
  buildTimeWindow,
  getTimeWindowState,
  parseTimeWindow,
} from 'dashboard/helper/timeWindow';

defineProps({
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

const toggleDay = key => {
  if (selectedDays.value.length === 1 && selectedDays.value.includes(key)) {
    return;
  }
  days.value = selectedDays.value.includes(key)
    ? selectedDays.value.filter(day => day !== key)
    : [...selectedDays.value, key];
};
</script>

<template>
  <div
    class="flex w-full min-w-0 flex-col gap-2 p-0"
    :class="{ 'pointer-events-none opacity-50': disabled }"
    :aria-disabled="disabled"
  >
    <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
      <label
        dir="ltr"
        class="flex min-w-0 flex-none items-center gap-2 text-xs text-n-slate-11"
      >
        <span>{{ t('AUTOMATION.TIME_WINDOW.FROM') }}</span>
        <TimeField
          v-model="from"
          class="w-28 flex-none"
          :disabled="disabled"
          :message-type="state === 'same' ? 'error' : 'info'"
        />
      </label>
      <label
        dir="ltr"
        class="flex min-w-0 flex-none items-center gap-2 text-xs text-n-slate-11"
      >
        <span>{{ t('AUTOMATION.TIME_WINDOW.TO') }}</span>
        <TimeField
          v-model="to"
          class="w-28 flex-none"
          :disabled="disabled"
          :message-type="state === 'same' ? 'error' : 'info'"
        />
      </label>
      <div
        class="flex shrink-0 flex-wrap items-center gap-x-2 gap-y-2"
        role="group"
        :aria-label="t('AUTOMATION.TIME_WINDOW.DAYS')"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('AUTOMATION.TIME_WINDOW.DAYS_LABEL') }}
        </span>
        <div class="flex shrink-0 items-center gap-1">
          <button
            v-for="day in dayOptions"
            :key="day.key"
            type="button"
            class="size-8 shrink-0 rounded-md p-0 text-xs font-medium outline outline-1 -outline-offset-1 focus-visible:outline-2 focus-visible:outline-n-brand"
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
      </div>
    </div>

    <p
      v-if="state === 'same'"
      class="m-0 text-xs leading-4 text-n-ruby-11"
      aria-live="polite"
    >
      {{ t('AUTOMATION.TIME_WINDOW.ERROR_SAME') }}
    </p>
  </div>
</template>
