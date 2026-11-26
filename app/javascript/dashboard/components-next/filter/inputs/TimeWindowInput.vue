<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import TimeField from 'next/time-field/TimeField.vue';
import {
  TIME_WINDOW_DAYS,
  buildTimeWindow,
  parseTimeWindow,
  summarizeTimeWindow,
} from 'dashboard/helper/timeWindow';

const modelValue = defineModel({ type: String, default: '' });

const { t } = useI18n();

const initial = parseTimeWindow(modelValue.value);
const from = ref(initial?.from || '');
const to = ref(initial?.to || '');
const days = ref(initial?.days || []);

const composed = computed(() =>
  buildTimeWindow({ from: from.value, to: to.value, days: days.value })
);
const summary = computed(() => summarizeTimeWindow(composed.value, t));

// Only resync from outside when the parent really changed the value (loading a saved rule,
// switching attribute); echoing our own output back would erase half-filled fields.
watch(modelValue, value => {
  if (value === composed.value) return;
  const parsed = parseTimeWindow(value);
  from.value = parsed?.from || '';
  to.value = parsed?.to || '';
  days.value = parsed?.days || [];
});

watch(composed, value => {
  if (value !== modelValue.value) modelValue.value = value;
});

const dayOptions = computed(() =>
  TIME_WINDOW_DAYS.map((key, index) => {
    const name = [
      t('DAYS_OF_WEEK.SUNDAY'),
      t('DAYS_OF_WEEK.MONDAY'),
      t('DAYS_OF_WEEK.TUESDAY'),
      t('DAYS_OF_WEEK.WEDNESDAY'),
      t('DAYS_OF_WEEK.THURSDAY'),
      t('DAYS_OF_WEEK.FRIDAY'),
      t('DAYS_OF_WEEK.SATURDAY'),
    ][index];
    return { key, name, short: name.slice(0, 3) };
  })
);

const toggleDay = key => {
  days.value = days.value.includes(key)
    ? days.value.filter(day => day !== key)
    : [...days.value, key];
};
</script>

<template>
  <div class="flex flex-col gap-2 min-w-0">
    <div class="flex flex-wrap items-end gap-2">
      <div class="w-36">
        <TimeField v-model="from" :label="t('AUTOMATION.TIME_WINDOW.FROM')" />
      </div>
      <div class="w-36">
        <TimeField v-model="to" :label="t('AUTOMATION.TIME_WINDOW.TO')" />
      </div>
    </div>
    <div
      class="flex flex-wrap gap-1"
      role="group"
      :aria-label="t('AUTOMATION.TIME_WINDOW.DAYS')"
    >
      <button
        v-for="day in dayOptions"
        :key="day.key"
        type="button"
        class="px-2 py-1 text-xs rounded-md outline outline-1 -outline-offset-1"
        :class="
          days.includes(day.key)
            ? 'bg-n-brand text-white outline-n-brand'
            : 'bg-n-solid-1 text-n-slate-12 outline-n-weak hover:bg-n-alpha-2'
        "
        :aria-pressed="days.includes(day.key)"
        :aria-label="day.name"
        :title="day.name"
        @click="toggleDay(day.key)"
      >
        {{ day.short }}
      </button>
    </div>
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('AUTOMATION.TIME_WINDOW.HINT') }}
    </p>
    <p v-if="summary" class="m-0 text-sm text-n-slate-12" aria-live="polite">
      {{ summary }}
    </p>
  </div>
</template>
