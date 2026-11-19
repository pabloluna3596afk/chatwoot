<script setup>
import { computed } from 'vue';
import {
  templateDataEligible,
  templateVariables,
  variableTokens,
} from './templateData';

const props = defineProps({ template: { type: Object, required: true } });
const missing = computed(() =>
  variableTokens(props.template.missing_variables || [])
);
const state = computed(() => {
  if (!templateDataEligible(props.template)) return null;
  if (!templateVariables(props.template).length) return 'NONE';
  return missing.value ? 'MISSING' : 'AUTO';
});
</script>

<template>
  <span v-if="!state">—</span>
  <span
    v-else
    v-tooltip="
      state === 'MISSING'
        ? $t('WHATSAPP_TEMPLATE_MGMT.DATA_STATE.MISSING_TOOLTIP', {
            variables: missing,
          })
        : ''
    "
    class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
    :class="
      state === 'MISSING'
        ? 'bg-n-amber-3 text-n-amber-11'
        : state === 'AUTO'
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-alpha-2 text-n-slate-11'
    "
    data-testid="template-data"
  >
    {{
      $t(`WHATSAPP_TEMPLATE_MGMT.DATA_STATE.${state}`, { variables: missing })
    }}
  </span>
</template>
