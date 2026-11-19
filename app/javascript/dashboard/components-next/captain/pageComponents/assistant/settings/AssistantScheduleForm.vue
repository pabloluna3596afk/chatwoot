<script setup>
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { nameRichFrom } = useAssistantName(() => props.assistant);

const RESPONSE_WINDOW = {
  ALWAYS: 'always',
  BUSINESS_HOURS: 'business_hours',
  OUTSIDE_BUSINESS_HOURS: 'outside_business_hours',
};

const OPTIONS = Object.values(RESPONSE_WINDOW);

const selected = ref(RESPONSE_WINDOW.ALWAYS);

const handleSubmit = () => {
  emit('submit', {
    config: { ...props.assistant.config, response_window: selected.value },
  });
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) {
      selected.value =
        newAssistant.config?.response_window || RESPONSE_WINDOW.ALWAYS;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-3">
      <RadioCard
        v-for="option in OPTIONS"
        :id="option"
        :key="option"
        :label="
          t(`CAPTAIN.ASSISTANTS.FORM.SCHEDULE.${option.toUpperCase()}.LABEL`)
        "
        :description="
          nameRichFrom(
            t(`CAPTAIN.ASSISTANTS.FORM.SCHEDULE.${option.toUpperCase()}.DESC`)
          )
        "
        :is-active="selected === option"
        @select="selected = $event"
      />
    </div>
    <p class="text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.SCHEDULE.HINT') }}
    </p>
    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
