<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  config: { type: Object, default: () => ({}) },
  linkToFollowup: { type: Boolean, default: false },
});
const { t } = useI18n();
const route = useRoute();
const summary = computed(() => {
  const followup = props.config.followup || {};
  const nudges =
    followup.inactivity_enabled !== false && (followup.max_nudges ?? 1) > 0;
  const mode = props.config.auto_resolve_mode ?? 'evaluated';
  const params = {
    after: followup.inactivity_after_minutes ?? 30,
    count: followup.max_nudges ?? 1,
    minutes: props.config.auto_resolve_after ?? 60,
  };
  if (mode === 'disabled')
    return nudges
      ? t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.DISABLED_NUDGES')
      : t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.DISABLED');
  return nudges
    ? t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.NUDGES_SUMMARY', params)
    : t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.SUMMARY', params);
});
</script>

<template>
  <div
    class="flex flex-col gap-2 text-body-main text-n-slate-11"
    data-testid="closure-summary"
  >
    <p class="m-0">{{ summary }}</p>
    <p class="m-0">{{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.SILENCE_HELP') }}</p>
    <RouterLink
      v-if="linkToFollowup"
      :to="{
        name: 'captain_assistants_settings_followup_index',
        params: route.params,
      }"
      class="text-n-brand underline"
    >
      {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.FOLLOWUP_LINK') }}
    </RouterLink>
  </div>
</template>
