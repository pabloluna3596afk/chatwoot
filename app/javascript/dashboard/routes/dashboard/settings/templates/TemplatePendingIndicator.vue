<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { hasPendingVariables, variableTokens } from './templateData';
const props = defineProps({ template: { type: Object, required: true } });
const { t } = useI18n();
const label = computed(() =>
  t('WHATSAPP_TEMPLATE_MGMT.MISSING_VARIABLES', {
    variables: variableTokens(props.template.missing_variables || []),
  })
);
</script>

<template>
  <span
    v-if="hasPendingVariables(template)"
    v-tooltip.top="label"
    tabindex="0"
    role="img"
    :aria-label="label"
    class="i-lucide-circle-alert size-3.5 shrink-0 text-n-amber-11"
    data-testid="template-pending"
  />
</template>
