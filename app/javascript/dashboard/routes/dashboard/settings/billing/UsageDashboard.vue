<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AiUsageAPI from 'dashboard/api/aiUsage';
import ButtonV4 from 'next/button/Button.vue';
import InfoChip from 'next/ListCard/InfoChip.vue';
import BagIcon from 'next/plans/BagIcon.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import BillingMeter from './components/BillingMeter.vue';
import { formatBillingDate, formatBillingDateRange } from './billingDate';

const props = defineProps({
  planName: { type: String, default: '' },
  planStatus: { type: String, default: '' },
  isLoadingLimits: { type: Boolean, default: false },
  renewalDate: { type: String, default: '' },
  periodEnd: { type: String, default: '' },
  responseLimits: { type: Object, default: null },
  copilotLimits: { type: Object, default: null },
  internalLimits: { type: Object, default: null },
  storageLimits: { type: Object, default: null },
  agentsMeterData: { type: Object, default: null },
  inboxesMeterData: { type: Object, default: null },
  expiredMessage: { type: String, default: '' },
});
const emit = defineEmits(['comparePlans', 'billing']);
const { t, locale } = useI18n();
const loading = ref(true);
const isLoadingUsage = computed(() => loading.value || props.isLoadingLimits);
const error = ref(false);
const usage = ref({ daily: [] });
const bagModeLabels = computed(() => ({
  shared: t('BILLING_SETTINGS.USAGE.BAG_MODES.SHARED'),
  unlimited: t('BILLING_SETTINGS.USAGE.BAG_MODES.UNLIMITED'),
  not_included: t('BILLING_SETTINGS.USAGE.BAG_MODES.NOT_INCLUDED'),
}));

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1000;
const numberFormatter = computed(() => new Intl.NumberFormat(locale.value));
const bags = computed(() =>
  [
    {
      key: 'captain_responses',
      title: t('BILLING_SETTINGS.USAGE.BAGS.ASSISTANT'),
      limits: props.responseLimits,
      color: 'rgb(var(--blue-9))',
      legendColor: 'bg-n-blue-9',
    },
    {
      key: 'copilot',
      title: t('BILLING_SETTINGS.USAGE.BAGS.COPILOT'),
      limits: props.copilotLimits,
      color: 'rgb(var(--violet-9))',
      legendColor: 'bg-n-violet-9',
    },
    {
      key: 'internal',
      title: t('BILLING_SETTINGS.USAGE.BAGS.INTERNAL'),
      limits: props.internalLimits,
      color: 'rgb(var(--teal-9))',
      legendColor: 'bg-n-teal-9',
    },
  ].map(bag => {
    const percent =
      bag.limits?.totalCount > 0
        ? (bag.limits.consumed / bag.limits.totalCount) * 100
        : 0;
    return {
      ...bag,
      percent: Math.min(100, percent),
      percentLabel: t('BILLING_SETTINGS.USAGE.PERCENT_USED', {
        percent:
          percent > 0 && percent < 1
            ? `<${numberFormatter.value.format(1)}`
            : numberFormatter.value.format(Math.round(percent)),
      }),
      mode:
        usage.value.bag_modes?.[bag.key] ||
        (bag.limits?.totalCount > 0 ? 'included' : 'not_included'),
    };
  })
);

const chartRows = computed(() => {
  const { period_start: start, period_end: end, daily } = usage.value;
  if (!start || !end) return [];

  // API buckets are UTC dates; period_end is an exclusive timestamp.
  const firstDay = Date.parse(
    `${new Date(start).toISOString().slice(0, 10)}T00:00:00Z`
  );
  const lastInstant = Math.min(Date.now(), Date.parse(end) - 1);
  const days = new Map();
  for (let day = firstDay; day <= lastInstant; day += DAY_IN_MILLISECONDS) {
    const key = new Date(day).toISOString().slice(0, 10);
    days.set(key, { day: key, captain_responses: 0, copilot: 0, internal: 0 });
  }
  daily.forEach(({ day, bucket, messages }) => {
    if (days.has(day)) days.get(day)[bucket] = messages;
  });
  return [...days.values()];
});
const dateLabel = day =>
  new Intl.DateTimeFormat(locale.value, {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  }).format(new Date(`${day}T00:00:00Z`));
const chartData = computed(() => ({
  categories: chartRows.value.map(row => dateLabel(row.day)),
  series: bags.value.map(bag => ({
    id: bag.key,
    label: bag.title,
    color: bag.color,
    data: chartRows.value.map(row => row[bag.key]),
  })),
}));
const formatChartValue = value => numberFormatter.value.format(value);
const chartStepSize = ({ min, max, tickCount }) =>
  Math.max(1, Math.ceil((max - min) / Math.max(tickCount - 1, 1)));
const dateRange = computed(() => usage.value.period_end || props.periodEnd);
const resetDate = computed(() =>
  dateRange.value ? formatBillingDate(dateRange.value, locale.value) : ''
);
const periodLabel = computed(() =>
  usage.value.period_start && usage.value.period_end
    ? formatBillingDateRange(
        usage.value.period_start,
        usage.value.period_end,
        locale.value
      )
    : ''
);
const empty = computed(
  () => !isLoadingUsage.value && !error.value && usage.value.daily.length === 0
);

onMounted(async () => {
  try {
    const { data } = await AiUsageAPI.get();
    usage.value = data;
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <section
    id="billing-panel-uso"
    role="tabpanel"
    aria-labelledby="billing-tab-uso"
    class="min-w-0 space-y-4"
  >
    <article class="rounded-xl shadow-sm border border-n-weak bg-n-solid-2 p-5">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.USAGE.CURRENT_PLAN') }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="mb-1 mt-1 text-heading-2">
              {{ planName || t('BILLING_SETTINGS.USAGE.FREE_PLAN') }}
            </h2>
            <InfoChip>
              {{ planStatus }}
            </InfoChip>
          </div>
          <p class="m-0 text-sm text-n-slate-11">
            {{ renewalDate || t('BILLING_SETTINGS.USAGE.FREE_PLAN') }}
          </p>
          <p v-if="resetDate" class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.USAGE.RESET_DATE', { date: resetDate }) }}
          </p>
        </div>
        <ButtonV4
          :label="t('PLAN_CATALOG.COMPARE')"
          sm
          intent="secondary"
          @click="emit('comparePlans')"
        />
      </div>
      <div
        v-if="expiredMessage"
        class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-ruby-8 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
        role="alert"
      >
        <span>{{ expiredMessage }}</span>
        <ButtonV4
          :label="t('BILLING_SETTINGS.USAGE.GO_TO_BILLING')"
          sm
          intent="secondary"
          @click="emit('billing')"
        />
      </div>
    </article>

    <div
      v-if="isLoadingUsage"
      class="grid min-h-36 gap-3 sm:grid-cols-3"
      aria-busy="true"
    >
      <div
        v-for="item in 3"
        :key="item"
        class="animate-pulse rounded-xl border border-n-weak bg-n-slate-2 dark:bg-n-solid-3"
      />
    </div>
    <div
      v-else-if="bags.length"
      class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3"
    >
      <article
        v-for="bag in bags"
        :key="bag.key"
        class="rounded-xl shadow-sm border border-n-weak bg-n-solid-2 p-5"
      >
        <h3 class="m-0 flex items-center gap-2 text-base font-medium">
          <BagIcon :bag="bag.key" class="size-4 shrink-0" />
          {{ bag.title }}
        </h3>
        <p
          v-if="bag.mode === 'included'"
          class="mb-3 mt-2 text-sm text-n-slate-11"
        >
          {{
            t('BILLING_SETTINGS.USAGE.USED_INCLUDED', {
              used: numberFormatter.format(bag.limits.consumed),
              included: numberFormatter.format(bag.limits.totalCount),
            })
          }}
        </p>
        <div
          v-if="bag.mode === 'included'"
          class="h-2 overflow-hidden rounded-full bg-n-slate-3"
          role="progressbar"
          :aria-label="bag.title"
          :aria-valuenow="bag.percent"
          :aria-valuetext="bag.percentLabel"
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <svg
            class="block h-2 w-full"
            viewBox="0 0 100 8"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect
              x="0"
              y="0"
              :width="bag.percent"
              height="8"
              :class="
                bag.limits.consumed >= bag.limits.totalCount
                  ? 'fill-n-ruby-9'
                  : bag.limits.consumed / bag.limits.totalCount >= 0.8
                    ? 'fill-n-amber-9'
                    : 'fill-n-blue-9'
              "
            />
          </svg>
        </div>
        <p
          v-if="bag.mode === 'included'"
          class="mb-0 mt-2 text-xs text-n-slate-11"
        >
          {{ bag.percentLabel }}
        </p>
        <p v-else class="mb-0 mt-2 text-sm text-n-slate-11">
          {{ bagModeLabels[bag.mode] }}
        </p>
      </article>
    </div>
    <p
      v-else-if="!isLoadingUsage"
      class="rounded-xl border border-n-weak p-5 text-sm text-n-slate-11"
    >
      {{ t('BILLING_SETTINGS.USAGE.NO_INCLUDED_BAGS') }}
    </p>

    <section
      class="min-w-0 rounded-xl shadow-sm border border-n-weak bg-n-solid-2 p-5"
      aria-labelledby="usage-chart-heading"
    >
      <h2 id="usage-chart-heading" class="mb-1 mt-0 text-heading-3">
        {{ t('BILLING_SETTINGS.USAGE.DAILY_TITLE') }}
      </h2>
      <p v-if="periodLabel" class="mb-3 mt-0 text-sm text-n-slate-11">
        {{ periodLabel }}
      </p>
      <ul
        class="mb-3 mt-0 flex flex-wrap gap-x-5 gap-y-2 p-0 list-none text-sm text-n-slate-11"
      >
        <li v-for="bag in bags" :key="bag.key" class="flex items-center gap-2">
          <span
            class="size-2 rounded-sm"
            :class="bag.legendColor"
            aria-hidden="true"
          />
          <BagIcon :bag="bag.key" class="size-4 shrink-0" />
          {{ bag.title }}
        </li>
      </ul>
      <div
        v-if="isLoadingUsage && !error"
        class="h-48 animate-pulse rounded-lg bg-n-slate-2 dark:bg-n-solid-3"
        aria-hidden="true"
      />
      <p v-if="error" class="m-0 text-sm text-n-ruby-11" role="alert">
        {{ t('BILLING_SETTINGS.USAGE.ERROR') }}
      </p>
      <p v-else-if="empty" class="m-0 text-sm text-n-slate-11">
        {{ t('BILLING_SETTINGS.USAGE.EMPTY') }}
      </p>
      <div
        v-if="!isLoadingUsage && !error && chartRows.length"
        class="relative min-w-0 max-w-full"
      >
        <BarChart
          :data="chartData"
          :aria-label="t('BILLING_SETTINGS.USAGE.CHART_LABEL')"
          :format-value="formatChartValue"
          :y-step-size="chartStepSize"
          :height="256"
          timeseries
        />
        <div class="sr-only">
          <table>
            <caption>
              {{
                t('BILLING_SETTINGS.USAGE.CHART_LABEL')
              }}
            </caption>
            <thead>
              <tr>
                <th>{{ t('BILLING_SETTINGS.USAGE.DATE') }}</th>
                <th>{{ t('BILLING_SETTINGS.USAGE.BAGS.ASSISTANT') }}</th>
                <th>{{ t('BILLING_SETTINGS.USAGE.BAGS.COPILOT') }}</th>
                <th>{{ t('BILLING_SETTINGS.USAGE.BAGS.INTERNAL') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in chartRows" :key="row.day">
                <th>{{ row.day }}</th>
                <td>{{ row.captain_responses }}</td>
                <td>{{ row.copilot }}</td>
                <td>{{ row.internal }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <section
      v-if="storageLimits || agentsMeterData || inboxesMeterData"
      class="grid gap-5 rounded-xl shadow-sm border border-n-weak bg-n-solid-2 py-5 sm:grid-cols-2 xl:grid-cols-3"
      :aria-label="t('BILLING_SETTINGS.USAGE.PLAN_RESOURCES')"
    >
      <BillingMeter
        v-if="storageLimits"
        :title="t('BILLING_SETTINGS.CAPTAIN.STORAGE')"
        v-bind="storageLimits"
        unit="bytes"
      />
      <BillingMeter
        v-if="agentsMeterData"
        :title="t('BILLING_SETTINGS.CAPTAIN.AGENTS')"
        v-bind="agentsMeterData"
      />
      <BillingMeter
        v-if="inboxesMeterData"
        :title="t('BILLING_SETTINGS.CAPTAIN.INBOXES')"
        v-bind="inboxesMeterData"
      />
    </section>
  </section>
</template>
