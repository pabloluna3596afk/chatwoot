<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import MenuPopover from 'next/dropdown-menu/MenuPopover.vue';
import Button from 'next/button/Button.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, default: '' },
  min: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { locale, t } = useI18n();
const open = ref(false);
const today = new Date();
const month = ref(new Date(today.getFullYear(), today.getMonth(), 1));
const dateValue = date =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
const todayValue = dateValue(today);
watch(open, value => {
  if (!value) return;
  const selected = props.modelValue || todayValue;
  const [year, number] = selected.split('-').map(Number);
  month.value = new Date(year, number - 1, 1);
});
const displayValue = computed(() => {
  if (!props.modelValue)
    return locale.value.startsWith('en') ? 'mm/dd/yyyy' : 'dd/mm/aaaa';
  const [year, number, day] = props.modelValue.split('-');
  return locale.value.startsWith('en')
    ? `${number}/${day}/${year}`
    : `${day}/${number}/${year}`;
});
const monthLabel = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    month: 'long',
    year: 'numeric',
  }).format(month.value)
);
const weekdays = computed(() =>
  Array.from({ length: 7 }, (_, index) =>
    new Intl.DateTimeFormat(locale.value, { weekday: 'short' }).format(
      new Date(2023, 0, 1 + index)
    )
  )
);
const days = computed(() => {
  const year = month.value.getFullYear();
  const number = month.value.getMonth();
  const offset = month.value.getDay();
  const count = new Date(year, number + 1, 0).getDate();
  return Array.from({ length: offset + count }, (_, index) =>
    index < offset
      ? null
      : dateValue(new Date(year, number, index - offset + 1))
  );
});
const moveMonth = offset => {
  month.value = new Date(
    month.value.getFullYear(),
    month.value.getMonth() + offset,
    1
  );
};
const selectDate = value => {
  emit('update:modelValue', value);
  open.value = false;
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-1">
    <span v-if="label" class="mb-0.5 text-heading-3 text-n-slate-12">{{
      label
    }}</span>
    <MenuPopover
      v-model:open="open"
      align="start"
      panel-class="w-72 max-w-[calc(100vw-2rem)]"
      :label="label"
    >
      <template #trigger="{ toggle }">
        <button
          type="button"
          :disabled="disabled"
          :aria-label="label"
          :aria-expanded="open"
          aria-haspopup="dialog"
          class="flex h-10 w-full items-center gap-2 rounded-lg px-3 text-sm text-n-slate-12 bg-n-alpha-black2 outline outline-1 outline-offset-[-1px] outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand disabled:opacity-50"
          @click="toggle"
        >
          <span class="i-lucide-calendar size-4 shrink-0 text-n-slate-11" />
          {{ displayValue }}
        </button>
      </template>
      <template #content>
        <div class="p-2">
          <div class="flex items-center justify-between gap-2 mb-2">
            <Button
              ghost
              slate
              xs
              icon="i-lucide-chevron-left"
              :aria-label="t('DATE_FIELD.PREVIOUS_MONTH')"
              @click="moveMonth(-1)"
            />
            <span
              aria-live="polite"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ monthLabel }}
            </span>
            <Button
              ghost
              slate
              xs
              icon="i-lucide-chevron-right"
              :aria-label="t('DATE_FIELD.NEXT_MONTH')"
              @click="moveMonth(1)"
            />
          </div>
          <div class="grid grid-cols-7 gap-1 text-center">
            <span
              v-for="day in weekdays"
              :key="day"
              class="text-xs text-n-slate-11 py-1"
            >
              {{ day }}
            </span>
            <template v-for="(value, index) in days" :key="value || index">
              <button
                v-if="value"
                type="button"
                :disabled="Boolean(min && value < min)"
                :aria-label="value"
                :aria-pressed="value === modelValue"
                :aria-current="value === todayValue ? 'date' : undefined"
                class="h-8 rounded-md text-sm disabled:opacity-30 disabled:cursor-not-allowed"
                :class="[
                  value === modelValue
                    ? 'bg-n-brand text-white'
                    : 'text-n-slate-12 hover:bg-n-alpha-2',
                  value === todayValue ? 'ring-1 ring-n-brand' : '',
                ]"
                @click="selectDate(value)"
              >
                {{ Number(value.slice(-2)) }}
              </button>
              <span v-else />
            </template>
          </div>
        </div>
      </template>
    </MenuPopover>
  </div>
</template>
