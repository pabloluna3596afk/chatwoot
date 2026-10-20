<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import PlanCompareButton from 'next/plans/PlanCompareButton.vue';
import OverviewPanel from './OverviewPanel.vue';
import ProgressMetric from './ProgressMetric.vue';

const props = defineProps({
  responseLimits: { type: Object, default: null },
  documentLimits: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['refresh', 'buy']);
const { t } = useI18n();
const { isOnChatwootCloud } = useAccount();
const { isAdmin } = useAdmin();

const canBuyCredits = computed(() => isOnChatwootCloud.value && isAdmin.value);

const meters = computed(() =>
  [
    {
      key: 'responses',
      label: t('CAPTAIN.OVERVIEW.V2.USAGE.CREDITS'),
      limits: props.responseLimits,
    },
    {
      key: 'documents',
      label: t('CAPTAIN.OVERVIEW.V2.USAGE.DOCUMENTS'),
      limits: props.documentLimits,
    },
  ].map(({ key, label, limits }) => {
    const known =
      Number.isFinite(limits?.consumed) && Number.isFinite(limits?.totalCount);
    const percentage =
      known && limits.totalCount > 0
        ? (limits.consumed / limits.totalCount) * 100
        : 0;
    return {
      key,
      label,
      known,
      used: known ? limits.consumed : undefined,
      total: known ? limits.totalCount : undefined,
      usageLabel: known
        ? t('CAPTAIN.OVERVIEW.V2.USAGE.USED', {
            percentage: new Intl.NumberFormat(undefined, {
              maximumFractionDigits: 1,
            }).format(percentage),
          })
        : '',
      valueLabel: known
        ? t('CAPTAIN.OVERVIEW.V2.USAGE.VALUE', {
            used: limits.consumed.toLocaleString(),
            total: limits.totalCount.toLocaleString(),
          })
        : t('PLAN_CATALOG.UNKNOWN'),
    };
  })
);
</script>

<template>
  <OverviewPanel
    class="[&>header]:h-auto [&>header]:flex-wrap [&>header]:gap-y-2"
    :title="$t('CAPTAIN.OVERVIEW.V2.USAGE.TITLE')"
  >
    <template #actions>
      <div class="flex flex-wrap items-center gap-2">
        <PlanCompareButton />
        <Button
          sm
          slate
          outline
          icon="i-lucide-refresh-cw"
          :aria-label="$t('CAPTAIN.OVERVIEW.V2.USAGE.REFRESH')"
          :is-loading="loading"
          @click="emit('refresh')"
        />
        <Button
          v-if="canBuyCredits"
          sm
          slate
          outline
          :label="$t('CAPTAIN.OVERVIEW.V2.USAGE.BUY_MORE')"
          @click="emit('buy')"
        />
      </div>
    </template>
    <div class="flex flex-col gap-5 p-5">
      <template v-for="meter in meters" :key="meter.key">
        <ProgressMetric
          v-if="meter.known || loading"
          v-bind="meter"
          :loading="loading"
        />
        <div
          v-else
          class="flex justify-between gap-3 text-sm text-n-slate-11"
          role="status"
        >
          <div>{{ meter.label }}</div>
          <div>{{ meter.valueLabel }}</div>
        </div>
      </template>
    </div>
  </OverviewPanel>
</template>
