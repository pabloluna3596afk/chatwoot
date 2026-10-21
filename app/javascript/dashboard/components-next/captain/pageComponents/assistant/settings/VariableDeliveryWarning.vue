<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ diagnostic: { type: Object, default: null } });
const { t } = useI18n();
</script>

<template>
  <p
    v-if="diagnostic"
    role="status"
    class="mb-0 rounded-lg border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-slate-12"
  >
    {{
      t('VARIABLES.DELIVERY_WARNING', {
        template: diagnostic.template,
        path: diagnostic.path,
        reason: t(`VARIABLES.STATUS.${diagnostic.status.toUpperCase()}`),
        at: diagnostic.at,
      })
    }}
  </p>
</template>
