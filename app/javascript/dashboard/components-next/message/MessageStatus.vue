<script setup>
import { computed, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { MESSAGE_STATUS } from './constants';

const { status } = defineProps({
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
});

const { t } = useI18n();

const progresIconSequence = [
  'i-lucide-clock-1',
  'i-lucide-clock-2',
  'i-lucide-clock-3',
  'i-lucide-clock-4',
  'i-lucide-clock-5',
  'i-lucide-clock-6',
  'i-lucide-clock-7',
  'i-lucide-clock-8',
  'i-lucide-clock-9',
  'i-lucide-clock-10',
  'i-lucide-clock-11',
  'i-lucide-clock-12',
];

const progessIcon = ref(progresIconSequence[0]);

const rotateIcon = () => {
  const currentIndex = progresIconSequence.indexOf(progessIcon.value);
  const nextIndex = (currentIndex + 1) % progresIconSequence.length;
  progessIcon.value = progresIconSequence[nextIndex];
};

useIntervalFn(rotateIcon, 500, {
  immediate: status === MESSAGE_STATUS.PROGRESS,
  immediateCallback: false,
});

const statusIcon = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'i-lucide-check',
    [MESSAGE_STATUS.DELIVERED]: 'i-lucide-check-check',
    [MESSAGE_STATUS.READ]: 'i-lucide-check-check',
  };

  return statusIconMap[status];
});

const statusColor = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'text-n-slate-10',
    [MESSAGE_STATUS.DELIVERED]: 'text-n-slate-10',
    [MESSAGE_STATUS.READ]: 'text-n-blue-11',
  };

  return statusIconMap[status];
});

const tooltipText = computed(() => {
  const statusTextMap = {
    [MESSAGE_STATUS.SENT]: t('CHAT_LIST.SENT'),
    [MESSAGE_STATUS.DELIVERED]: t('CHAT_LIST.DELIVERED'),
    [MESSAGE_STATUS.READ]: t('CHAT_LIST.MESSAGE_READ'),
    [MESSAGE_STATUS.PROGRESS]: t('CHAT_LIST.SENDING'),
  };

  return statusTextMap[status];
});
</script>

<template>
  <span
    v-if="status === MESSAGE_STATUS.PROGRESS"
    v-tooltip.top-start="tooltipText"
    :class="progessIcon"
    class="size-3.5 shrink-0 text-n-slate-10"
    role="img"
    :aria-label="tooltipText"
  />
  <span
    v-else
    v-tooltip.top-start="tooltipText"
    :class="[statusIcon, statusColor]"
    class="size-3.5 shrink-0"
    role="img"
    :aria-label="tooltipText"
  />
</template>
