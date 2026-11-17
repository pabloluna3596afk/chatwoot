<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InboxHealthAPI from 'dashboard/api/inboxHealth';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const MONTH_COUNT = 3;
const CATEGORY_ORDER = [
  'service',
  'marketing',
  'utility',
  'authentication',
  'referral_conversion',
];
const { t, locale } = useI18n();
const categoryNames = computed(() => ({
  service: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.service.NAME'
  ),
  marketing: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.marketing.NAME'
  ),
  utility: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.utility.NAME'
  ),
  authentication: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.authentication.NAME'
  ),
  referral_conversion: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.referral_conversion.NAME'
  ),
}));
const categoryHelpText = computed(() => ({
  service: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.service.HELP'
  ),
  marketing: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.marketing.HELP'
  ),
  utility: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.utility.HELP'
  ),
  authentication: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.authentication.HELP'
  ),
  referral_conversion: t(
    'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.CATEGORIES.referral_conversion.HELP'
  ),
}));
const months = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

function currentMonthKey() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
}

const selectedMonth = ref(currentMonthKey());

function monthLabel(month) {
  const [year, monthNumber] = month.split('-').map(Number);
  const label = new Intl.DateTimeFormat(locale.value, {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(year, monthNumber - 1, 1)));
  return label.replace(/^./u, first => first.toLocaleUpperCase(locale.value));
}

const tabs = computed(() =>
  months.value.map(({ month }) => ({ label: monthLabel(month), value: month }))
);
const selectedTabIndex = computed(() =>
  Math.max(
    0,
    tabs.value.findIndex(tab => tab.value === selectedMonth.value)
  )
);
const selectedSummary = computed(
  () => months.value.find(({ month }) => month === selectedMonth.value) || null
);
const numberFormat = computed(() => new Intl.NumberFormat(locale.value));
const formatNumber = value => numberFormat.value.format(value || 0);

const counts = computed(() => {
  const summary = selectedSummary.value;
  if (!summary) return null;

  const billable = summary.categories.reduce(
    (total, category) => total + category.billable,
    0
  );
  const free = summary.categories.reduce(
    (total, category) => total + category.free,
    0
  );
  const noData = summary.outgoing - billable - free - summary.app_sent;
  const coverageTotal = summary.outgoing - summary.app_sent;
  const coveragePercent = coverageTotal
    ? (summary.with_pricing / coverageTotal) * 100
    : 0;

  return {
    billable,
    free,
    noData,
    appSent: summary.app_sent,
    coverageTotal,
    coveragePercent,
    isPartial: coverageTotal > 0 && coveragePercent < 50,
  };
});

const hasOutgoing = computed(() => (selectedSummary.value?.outgoing || 0) > 0);
const hasPricing = computed(
  () => (selectedSummary.value?.with_pricing || 0) > 0
);
const orderedCategories = computed(() => {
  const categories = selectedSummary.value?.categories || [];
  return [...categories].sort((left, right) => {
    const leftIndex = CATEGORY_ORDER.indexOf(left.category);
    const rightIndex = CATEGORY_ORDER.indexOf(right.category);
    if (leftIndex < 0 && rightIndex < 0)
      return left.category.localeCompare(right.category);
    if (leftIndex < 0) return 1;
    if (rightIndex < 0) return -1;
    return leftIndex - rightIndex;
  });
});

const coverageMonths = computed(() =>
  months.value.map(summary => {
    const total = summary.outgoing - summary.app_sent;
    const percent = total
      ? Math.round((summary.with_pricing / total) * 100)
      : 0;
    return {
      ...summary,
      total,
      percent,
    };
  })
);

function categoryName(category) {
  return categoryNames.value[category] || category;
}

function categoryHelp(category) {
  return categoryHelpText.value[category] || '';
}

async function loadSummary() {
  isLoading.value = true;
  hasError.value = false;
  months.value = [];
  try {
    const response = await InboxHealthAPI.getMessagePricing(props.inboxId, {
      months: MONTH_COUNT,
    });
    months.value = response.data.months;
    selectedMonth.value = currentMonthKey();
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
}

function selectMonth(tab) {
  selectedMonth.value = tab.value;
}

onMounted(loadSummary);
watch(() => props.inboxId, loadSummary);
</script>

<template>
  <section class="space-y-4 rounded-lg border border-n-weak bg-n-solid-1 p-4">
    <div>
      <h3 class="mb-3 text-heading-4 text-n-slate-12">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TITLE') }}
      </h3>
      <p class="text-body-main text-n-slate-11">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="tabs.length" class="space-y-2">
      <span class="text-label-small text-n-slate-11">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.MONTH_SELECTOR') }}
      </span>
      <TabBar
        :tabs="tabs"
        :initial-active-tab="selectedTabIndex"
        :tab-list-label="
          t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.MONTH_SELECTOR')
        "
        @tab-changed="selectMonth"
      />
    </div>

    <div v-if="isLoading" class="flex items-center gap-2 py-2 text-n-slate-11">
      <Spinner :size="18" />
      <span>{{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.LOADING') }}</span>
    </div>

    <div v-else-if="hasError" class="space-y-2">
      <p class="text-body-main text-n-slate-11">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.ERROR') }}
      </p>
      <Button intent="secondary" size="sm" @click="loadSummary">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.RETRY') }}
      </Button>
    </div>

    <template v-else-if="selectedSummary && counts">
      <Banner v-if="counts.isPartial" color="amber">
        {{
          t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.PARTIAL', {
            withData: formatNumber(selectedSummary.with_pricing),
            total: formatNumber(counts.coverageTotal),
          })
        }}
      </Banner>

      <p v-if="!hasOutgoing" class="text-body-main text-n-slate-11">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.EMPTY') }}
      </p>

      <template v-else>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <p class="tabular-nums text-heading-2 text-n-slate-12">
              {{ formatNumber(counts.billable) }}
            </p>
            <p class="text-body-main text-n-slate-11">
              {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.BILLABLE') }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <p class="tabular-nums text-heading-2 text-n-slate-12">
              {{ formatNumber(counts.free) }}
            </p>
            <p class="text-body-main text-n-slate-11">
              {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.FREE') }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <p class="tabular-nums text-heading-2 text-n-slate-12">
              {{ formatNumber(counts.appSent) }}
            </p>
            <p class="text-body-main text-n-slate-11">
              {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.APP_SENT') }}
            </p>
            <p class="mt-1 text-sm text-n-slate-10">
              {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.APP_SENT_HELP') }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <p class="tabular-nums text-heading-2 text-n-slate-12">
              {{ formatNumber(counts.noData) }}
            </p>
            <p class="text-body-main text-n-slate-11">
              {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.NO_DATA') }}
            </p>
          </div>
        </div>

        <div v-if="hasPricing" class="overflow-x-auto">
          <table class="w-full border-collapse text-sm tabular-nums">
            <thead>
              <tr class="text-n-slate-11">
                <th
                  scope="col"
                  class="border-b border-n-weak px-3 py-2 text-start font-medium"
                >
                  {{
                    t(
                      'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TABLE.CATEGORY'
                    )
                  }}
                </th>
                <th
                  scope="col"
                  class="border-b border-n-weak px-3 py-2 text-end font-medium"
                >
                  {{
                    t(
                      'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TABLE.BILLABLE'
                    )
                  }}
                </th>
                <th
                  scope="col"
                  class="border-b border-n-weak px-3 py-2 text-end font-medium"
                >
                  {{
                    t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TABLE.FREE')
                  }}
                </th>
                <th
                  scope="col"
                  class="border-b border-n-weak px-3 py-2 text-end font-medium"
                >
                  {{
                    t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TABLE.TOTAL')
                  }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="category in orderedCategories"
                :key="category.category"
              >
                <td
                  class="border-b border-n-weak px-3 py-2 text-start text-n-slate-12"
                >
                  <span>{{ categoryName(category.category) }}</span>
                  <span
                    v-if="categoryHelp(category.category)"
                    class="block text-sm text-n-slate-10"
                  >
                    {{ categoryHelp(category.category) }}
                  </span>
                </td>
                <td
                  class="border-b border-n-weak px-3 py-2 text-end text-n-slate-12"
                >
                  {{ formatNumber(category.billable) }}
                </td>
                <td
                  class="border-b border-n-weak px-3 py-2 text-end text-n-slate-12"
                >
                  {{ formatNumber(category.free) }}
                </td>
                <td
                  class="border-b border-n-weak px-3 py-2 text-end text-n-slate-12"
                >
                  {{ formatNumber(category.billable + category.free) }}
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="font-medium text-n-slate-12">
                <td class="px-3 py-2 text-start">
                  {{
                    t(
                      'INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.TABLE.WITH_DATA'
                    )
                  }}
                </td>
                <td class="px-3 py-2 text-end">
                  {{ formatNumber(counts.billable) }}
                </td>
                <td class="px-3 py-2 text-end">
                  {{ formatNumber(counts.free) }}
                </td>
                <td class="px-3 py-2 text-end">
                  {{ formatNumber(selectedSummary.with_pricing) }}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      </template>

      <div class="space-y-2">
        <h4 class="text-label-large text-n-slate-12">
          {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.COVERAGE.TITLE') }}
        </h4>
        <div
          v-for="month in coverageMonths"
          :key="month.month"
          class="grid grid-cols-[5rem_minmax(0,1fr)] items-center gap-x-3 gap-y-1 sm:grid-cols-[7rem_minmax(0,1fr)_auto]"
        >
          <span class="text-sm text-n-slate-11">{{
            monthLabel(month.month)
          }}</span>
          <progress
            class="h-2 w-full accent-n-brand"
            :value="month.percent"
            max="100"
            :aria-label="`${month.percent}%`"
          />
          <span
            class="col-span-2 text-sm tabular-nums text-n-slate-11 sm:col-span-1 sm:text-end"
          >
            {{
              t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.COVERAGE.ROW', {
                withData: formatNumber(month.with_pricing),
                total: formatNumber(month.total),
                percent: month.percent,
              })
            }}
          </span>
        </div>
      </div>

      <p class="text-sm text-n-slate-10">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.MESSAGE_PRICING.FOOTNOTE') }}
      </p>
    </template>
  </section>
</template>
