<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow, parseISO } from 'date-fns';
import { enUS, es } from 'date-fns/locale';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import BagIcon from 'dashboard/components-next/plans/BagIcon.vue';
import usageBreakdownApi from 'dashboard/api/captain/usageBreakdown';
import OverviewPanel from './OverviewPanel.vue';

const BUCKETS = [
  { id: 'captain_responses' },
  { id: 'copilot' },
  { id: 'internal' },
];

const { t, locale } = useI18n();
const { isAdmin } = useAdmin();
const result = ref(null);
const selectedBucket = ref('captain_responses');
const loading = ref(false);
const failed = ref(false);

const buckets = computed(() => result.value?.buckets || {});
const bucketLabel = bucket => {
  if (bucket.id === 'copilot') return t('BILLING_SETTINGS.USAGE.BAGS.COPILOT');
  if (bucket.id === 'internal')
    return t('BILLING_SETTINGS.USAGE.BAGS.INTERNAL');
  return t('BILLING_SETTINGS.USAGE.BAGS.ASSISTANT');
};
const selectedRows = computed(() => buckets.value[selectedBucket.value] || []);
const periodIsEmpty = computed(() => !result.value?.period_start);
const selectedBucketIsEmpty = computed(
  () => periodIsEmpty.value || selectedRows.value.length === 0
);
const maxUnits = computed(() =>
  Math.max(0, ...selectedRows.value.map(row => Number(row.units) || 0))
);

const barWidth = row =>
  `${maxUnits.value ? ((Number(row.units) || 0) / maxUnits.value) * 100 : 0}%`;

const load = async () => {
  if (!isAdmin.value) return;
  loading.value = true;
  failed.value = false;
  try {
    const response = await usageBreakdownApi.getUsageBreakdown();
    result.value = response.data;
    const totals = BUCKETS.map(bucket => ({
      id: bucket.id,
      units: (result.value.buckets?.[bucket.id] || []).reduce(
        (total, row) => total + (Number(row.units) || 0),
        0
      ),
    }));
    selectedBucket.value = totals.reduce(
      (largest, bucket) => (bucket.units > largest.units ? bucket : largest),
      totals[0]
    ).id;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const formatDate = date =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
  }).format(new Date(date));

const relativeDate = date =>
  formatDistanceToNow(parseISO(date), {
    addSuffix: true,
    locale: locale.value.startsWith('es') ? es : enUS,
  });

onMounted(load);
</script>

<template>
  <OverviewPanel :title="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.TITLE')">
    <template #actions>
      <Button
        sm
        slate
        outline
        icon="i-lucide-refresh-cw"
        :aria-label="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.REFRESH')"
        :is-loading="loading"
        @click="load"
      />
    </template>

    <div class="flex flex-col gap-5 p-5">
      <p
        v-if="result?.period_start"
        class="text-body-small text-n-slate-11"
        data-testid="usage-period"
      >
        {{
          $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.PERIOD', {
            start: formatDate(result.period_start),
            end: formatDate(result.period_end),
          })
        }}
      </p>
      <div
        class="flex flex-wrap gap-2"
        role="tablist"
        :aria-label="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.BAGS_LABEL')"
      >
        <button
          v-for="bucket in BUCKETS"
          :key="bucket.id"
          type="button"
          role="tab"
          class="inline-flex min-h-9 items-center gap-2 rounded-lg px-3 text-body-small transition-colors"
          :class="
            selectedBucket === bucket.id
              ? 'bg-n-brand/10 text-n-brand'
              : 'text-n-slate-11 hover:bg-n-slate-2'
          "
          :aria-selected="selectedBucket === bucket.id"
          @click="selectedBucket = bucket.id"
        >
          <BagIcon :bag="bucket.id" class="size-4 shrink-0" />
          <span>{{ bucketLabel(bucket) }}</span>
        </button>
      </div>

      <div
        v-if="loading"
        class="flex flex-col gap-5"
        :aria-label="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.LOADING')"
      >
        <div v-for="index in 3" :key="index" class="flex flex-col gap-3">
          <div class="h-4 w-2/5 animate-pulse rounded bg-n-slate-3" />
          <div class="h-3 w-full animate-pulse rounded bg-n-slate-2" />
        </div>
      </div>

      <div v-else-if="failed" class="flex items-center justify-between gap-3">
        <p class="text-body-main text-n-ruby-9" role="alert">
          {{ $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.ERROR') }}
        </p>
        <Button
          sm
          slate
          outline
          :label="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.RETRY')"
          :aria-label="$t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.RETRY')"
          @click="load"
        />
      </div>

      <p
        v-else-if="selectedBucketIsEmpty"
        class="text-body-main text-n-slate-11"
        role="status"
      >
        {{ $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.EMPTY') }}
      </p>

      <ul v-else class="flex flex-col gap-5">
        <li
          v-for="row in selectedRows"
          :key="row.feature"
          class="flex flex-col gap-2"
        >
          <div
            class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
          >
            <span class="text-body-main font-medium text-n-slate-12">{{
              row.name
            }}</span>
            <span class="text-body-small tabular-nums text-n-slate-11">
              <span>
                {{
                  $t(
                    'CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.OPERATIONS',
                    row.operations
                  )
                }}
              </span>
              <span
                aria-hidden="true"
                class="mx-2 inline-block h-3 w-px bg-n-slate-6 align-middle"
              />
              <span>
                {{ $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.UNITS', row.units) }}
              </span>
            </span>
          </div>
          <div
            class="h-1.5 w-full overflow-hidden rounded-full bg-n-slate-3"
            role="progressbar"
            aria-valuemin="0"
            :aria-valuemax="maxUnits || 1"
            :aria-valuenow="Number(row.units) || 0"
            :aria-label="
              $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.BAR_LABEL', {
                name: row.name,
              })
            "
          >
            <div
              class="h-full rounded-full bg-n-brand"
              :style="{ width: barWidth(row) }"
            />
          </div>
          <p class="text-caption text-n-slate-10">
            {{
              $t('CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.LAST_USED', {
                date: relativeDate(row.last_used_at),
              })
            }}
          </p>
        </li>
      </ul>
    </div>
  </OverviewPanel>
</template>
