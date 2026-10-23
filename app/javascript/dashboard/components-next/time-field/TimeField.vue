<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import MenuPopover from 'next/dropdown-menu/MenuPopover.vue';
import Input from 'next/input/Input.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  message: { type: String, default: '' },
  messageType: { type: String, default: 'info' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const MINUTES_PER_STEP = 15;
const MINUTES_PER_DAY = 24 * 60;
const open = ref(false);
const draft = ref(props.modelValue);
const invalid = ref(false);
const list = ref(null);
watch(
  () => props.modelValue,
  value => {
    draft.value = value;
    invalid.value = false;
  }
);
const times = Array.from(
  { length: MINUTES_PER_DAY / MINUTES_PER_STEP },
  (_, index) => {
    const minutes = index * MINUTES_PER_STEP;
    return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
  }
);
const selectedTime = computed(() => {
  const now = new Date();
  const [hours, minutes] = (
    props.modelValue || `${now.getHours()}:${now.getMinutes()}`
  )
    .split(':')
    .map(Number);
  return times[
    Math.min(
      times.length - 1,
      Math.round((hours * 60 + minutes) / MINUTES_PER_STEP)
    )
  ];
});
watch(open, async value => {
  if (!value) return;
  await nextTick();
  list.value
    ?.querySelector('[data-centered="true"]')
    ?.scrollIntoView?.({ block: 'center' });
});
const selectTime = value => {
  draft.value = value;
  invalid.value = false;
  emit('update:modelValue', value);
  open.value = false;
};
const validate = () => {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.value)) {
    invalid.value = true;
    draft.value = props.modelValue;
    return;
  }
  invalid.value = false;
  emit('update:modelValue', draft.value);
};
</script>

<template>
  <MenuPopover
    v-model:open="open"
    align="start"
    panel-class="w-40 max-w-[calc(100vw-2rem)]"
    :label="label"
  >
    <template #trigger="{ toggle }">
      <div class="w-full relative">
        <Input
          v-model="draft"
          :label="label"
          :disabled="disabled"
          placeholder="HH:mm"
          :aria-expanded="open"
          :aria-invalid="invalid"
          aria-haspopup="dialog"
          :message="invalid ? t('DATE_FIELD.INVALID_TIME') : message"
          :message-type="invalid ? 'error' : messageType"
          custom-input-class="!ps-9"
          @click.stop="toggle"
          @blur="validate"
          @enter="validate"
        >
          <template #prefix>
            <span
              class="pointer-events-none absolute start-3 z-10 i-lucide-clock size-4 text-n-slate-11"
              :class="label ? 'top-9' : 'top-3'"
            />
          </template>
        </Input>
      </div>
    </template>
    <template #content>
      <div
        ref="list"
        class="max-h-60 overflow-y-auto p-1"
        role="listbox"
        :aria-label="label"
      >
        <button
          v-for="value in times"
          :key="value"
          type="button"
          role="option"
          :aria-selected="value === modelValue"
          :data-centered="value === selectedTime"
          class="w-full rounded-md px-3 py-2 text-sm text-start"
          :class="
            value === modelValue
              ? 'bg-n-brand text-white'
              : 'text-n-slate-12 hover:bg-n-alpha-2'
          "
          @click="selectTime(value)"
        >
          {{ value }}
        </button>
      </div>
    </template>
  </MenuPopover>
</template>
