<script setup>
import { computed, onMounted, ref } from 'vue';
import { parseISO } from 'date-fns';
import { useI18n } from 'vue-i18n';
import AiUsageAPI from 'dashboard/api/aiUsage';
import ButtonV4 from 'next/button/Button.vue';
import BillingMeter from './components/BillingMeter.vue';

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

const bags = computed(() =>
  [
    {
      key: 'captain_responses',
      title: t('BILLING_SETTINGS.USAGE.BAGS.ASSISTANT'),
      limits: props.responseLimits,
    },
    {
      key: 'copilot',
      title: t('BILLING_SETTINGS.USAGE.BAGS.COPILOT'),
      limits: props.copilotLimits,
    },
    {
      key: 'internal',
      title: t('BILLING_SETTINGS.USAGE.BAGS.INTERNAL'),
      limits: props.internalLimits,
    },
  ].filter(bag => bag.limits?.totalCount > 0)
);

const chartRows = computed(() => {
  const days = new Map();
  usage.value.daily.forEach(({ day, bucket, messages }) => {
    if (!days.has(day))
      days.set(day, { day, captain_responses: 0, copilot: 0, internal: 0 });
    days.get(day)[bucket] = messages;
  });
  return [...days.values()].sort((a, b) => a.day.localeCompare(b.day));
});
const sourceTotals = computed(() =>
  [
    ['captain_responses', t('BILLING_SETTINGS.USAGE.SOURCES.ASSISTANT')],
    ['copilot', t('BILLING_SETTINGS.USAGE.SOURCES.COPILOT')],
    ['internal', t('BILLING_SETTINGS.USAGE.SOURCES.INTERNAL')],
  ]
    .map(([key, label]) => ({
      key,
      label,
      total: chartRows.value.reduce((sum, row) => sum + row[key], 0),
    }))
    .sort((a, b) => b.total - a.total)
);
const maxDaily = computed(() =>
  Math.max(
    1,
    ...chartRows.value.map(
      row => row.captain_responses + row.copilot + row.internal
    )
  )
);
const dateLabel = day =>
  new Intl.DateTimeFormat(locale.value, {
    day: 'numeric',
    month: 'short',
  }).format(parseISO(`${day}T12:00:00Z`));
const dateRange = computed(() => usage.value.period_end || props.periodEnd);
const resetDate = computed(() =>
  dateRange.value
    ? new Intl.DateTimeFormat(locale.value, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      }).format(parseISO(`${dateRange.value.slice(0, 10)}T12:00:00Z`))
    : ''
);
const empty = computed(
  () => !isLoadingUsage.value && !error.value && chartRows.value.length === 0
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
    class="space-y-4"
  >
    <article
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:p-6 dark:bg-n-solid-3"
    >
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.USAGE.CURRENT_PLAN') }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="mb-1 mt-1 text-heading-2">
              {{ planName || t('BILLING_SETTINGS.USAGE.FREE_PLAN') }}
            </h2>
            <span
              class="rounded-full bg-n-slate-3 px-2 py-1 text-xs text-n-slate-11"
            >
              {{ planStatus }}
            </span>
          </div>
          <p class="m-0 text-sm text-n-slate-11">
            {{ renewalDate || t('BILLING_SETTINGS.USAGE.FREE_PLAN') }}
          </p>
        </div>
        <ButtonV4
          :label="t('PLAN_CATALOG.COMPARE')"
          sm
          variant="outline"
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
          variant="outline"
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
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 dark:bg-n-solid-3"
      >
        <h3 class="m-0 text-base font-medium">{{ bag.title }}</h3>
        <p class="mb-3 mt-2 text-sm text-n-slate-11">
          {{
            t('BILLING_SETTINGS.USAGE.USED_INCLUDED', {
              used: bag.limits.consumed,
              included: bag.limits.totalCount,
            })
          }}
        </p>
        <div
          class="h-2 overflow-hidden rounded-full bg-n-slate-3"
          role="progressbar"
          :aria-label="bag.title"
          :aria-valuenow="
            Math.min(
              100,
              Math.round((bag.limits.consumed / bag.limits.totalCount) * 100)
            )
          "
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
              :width="
                Math.min(
                  100,
                  Math.round(
                    (bag.limits.consumed / bag.limits.totalCount) * 100
                  )
                )
              "
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
        <p class="mb-0 mt-2 text-xs text-n-slate-11">
          {{
            t('BILLING_SETTINGS.USAGE.PERCENT_USED', {
              percent: Math.round(
                (bag.limits.consumed / bag.limits.totalCount) * 100
              ),
            })
          }}
          <span v-if="resetDate" class="block pt-1">
            {{ t('BILLING_SETTINGS.USAGE.RESET_DATE', { date: resetDate }) }}
          </span>
        </p>
      </article>
    </div>
    <p
      v-else-if="!isLoadingUsage"
      class="rounded-xl border border-n-weak p-5 text-sm text-n-slate-11"
    >
      {{ t('BILLING_SETTINGS.USAGE.NO_INCLUDED_BAGS') }}
    </p>

    <div class="grid gap-4 lg:grid-cols-3">
      <section
        class="min-h-60 rounded-xl border border-n-weak bg-n-solid-1 p-4 dark:bg-n-solid-3 lg:col-span-2"
        aria-labelledby="usage-chart-heading"
      >
        <h2 id="usage-chart-heading" class="mb-3 mt-0 text-heading-3">
          {{ t('BILLING_SETTINGS.USAGE.DAILY_TITLE') }}
        </h2>
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
        <div v-else-if="!isLoadingUsage" class="overflow-x-auto">
          <svg
            class="h-48 min-w-[32rem] w-full"
            viewBox="0 0 600 190"
            role="img"
            :aria-label="t('BILLING_SETTINGS.USAGE.CHART_LABEL')"
          >
            <g
              v-for="(row, index) in chartRows"
              :key="row.day"
              :transform="`translate(${index * (560 / chartRows.length) + 24}, 0)`"
            >
              <rect
                v-for="(segment, segmentIndex) in [
                  row.captain_responses,
                  row.copilot,
                  row.internal,
                ]"
                :key="segmentIndex"
                :x="segmentIndex * 8"
                :y="160 - (segment / maxDaily) * 130"
                width="6"
                :height="Math.max(1, (segment / maxDaily) * 130)"
                :class="
                  ['fill-n-blue-9', 'fill-n-violet-9', 'fill-n-teal-9'][
                    segmentIndex
                  ]
                "
              />
              <text
                v-if="index % Math.ceil(chartRows.length / 8) === 0"
                x="0"
                y="180"
                class="fill-n-slate-11 text-[10px]"
              >
                {{ dateLabel(row.day) }}
              </text>
            </g>
          </svg>
          <table class="sr-only">
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
      </section>
      <section
        class="min-h-60 rounded-xl border border-n-weak bg-n-solid-1 p-4 dark:bg-n-solid-3"
        aria-labelledby="usage-sources-heading"
      >
        <h2 id="usage-sources-heading" class="mb-3 mt-0 text-heading-3">
          {{ t('BILLING_SETTINGS.USAGE.TOP_SOURCES') }}
        </h2>
        <p v-if="error" class="m-0 text-sm text-n-slate-11">
          {{ t('BILLING_SETTINGS.USAGE.ERROR') }}
        </p>
        <ol v-else class="m-0 space-y-3 ps-5 text-sm">
          <li
            v-for="source in sourceTotals"
            :key="source.key"
            class="flex justify-between gap-3"
          >
            <span>{{ source.label }}</span>
            <strong>{{ source.total }}</strong>
          </li>
        </ol>
      </section>
    </div>

    <section
      v-if="storageLimits || agentsMeterData || inboxesMeterData"
      class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3"
      :aria-label="t('BILLING_SETTINGS.USAGE.PLAN_RESOURCES')"
    >
      <BillingMeter
        v-if="storageLimits"
        :title="t('BILLING_SETTINGS.CAPTAIN.STORAGE')"
        v-bind="storageLimits"
        :period-end="periodEnd"
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
