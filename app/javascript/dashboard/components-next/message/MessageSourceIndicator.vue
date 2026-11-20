<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageSource } from 'dashboard/composables/useMessageSource';

const props = defineProps({
  contentAttributes: { type: Object, default: () => ({}) },
  iconClass: { type: String, default: 'size-4 text-n-slate-11' },
});

const { t } = useI18n();
const { source, icon, i18nKey, hasSource } = useMessageSource(
  computed(() => props.contentAttributes)
);

const tooltip = computed(() => {
  if (!hasSource.value) return '';

  const { type, id, name } = source.value;
  if (name && i18nKey.value) {
    return t(i18nKey.value, { name });
  }

  const typeLabel = t(`MESSAGE_SOURCE.TYPE_${type.toUpperCase()}`);
  return id
    ? t('MESSAGE_SOURCE.FALLBACK', { type: typeLabel, id })
    : t('MESSAGE_SOURCE.WITHOUT_ID', { type: typeLabel });
});
</script>

<template>
  <span
    v-if="hasSource && icon"
    v-tooltip.top="tooltip"
    :class="[icon, iconClass]"
    role="img"
    :aria-label="tooltip"
    data-testid="message-source-indicator"
  />
</template>
