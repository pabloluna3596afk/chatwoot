<script setup>
/* Catalog fields and repeated copy use translation keys derived at runtime. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  matchesPlan,
  planViewProps,
  usePlanPresentation,
} from './planPresentation';

const props = defineProps({
  ...planViewProps,
  plans: { type: Array, required: true },
});
const { t } = useI18n();
const {
  rows,
  features,
  baseFeatures,
  limitValue,
  value,
  money,
  pricing,
  isIncluded,
} = usePlanPresentation();
const limitRows = computed(() => rows(props.plans));
const featureRows = computed(() => features(props.plans));
const baseFeatureRows = computed(() => baseFeatures(props.plans));
</script>

<template>
  <div class="space-y-3">
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('PLAN_CATALOG.TABLE_HINT') }}
    </p>
    <div
      role="region"
      :aria-label="t('PLAN_CATALOG.DETAIL')"
      tabindex="0"
      class="max-h-[36rem] overflow-auto rounded-2xl border border-n-weak focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
    >
      <table
        class="w-full border-separate border-spacing-0 text-sm text-n-slate-12"
      >
        <caption class="sr-only">
          {{
            t('PLAN_CATALOG.DETAIL')
          }}
        </caption>
        <thead class="sticky top-0 z-20">
          <tr>
            <th
              scope="col"
              class="sticky start-0 z-30 min-w-48 border-b border-n-weak bg-n-solid-1 p-5 text-start dark:bg-n-solid-3"
            >
              {{ t('PLAN_CATALOG.PLAN') }}
            </th>
            <th
              v-for="plan in plans"
              :key="plan.id"
              scope="col"
              class="min-w-40 border-b border-n-weak bg-n-solid-1 p-5 dark:bg-n-solid-3"
              :class="{
                '!bg-n-blue-3':
                  matchesPlan(plan, currentPlanId) ||
                  plan.feature_keys.includes(requiredFeature),
              }"
            >
              {{ plan.name }}
              <div
                v-if="matchesPlan(plan, currentPlanId)"
                class="mt-1 block text-xs font-normal text-n-blue-12"
              >
                {{ t('PLAN_CATALOG.CURRENT') }}
              </div>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-medium dark:bg-n-solid-3"
            >
              {{ t('PLAN_CATALOG.PRICE') }}
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              <div class="font-semibold">
                <template v-if="pricing(plan).monthly > 0">
                  {{ money(pricing(plan).monthly) }}
                </template>
                <template v-else>
                  {{ t('PLAN_CATALOG.FREE') }}
                </template>
                <span
                  v-if="pricing(plan).monthly > 0"
                  class="font-normal text-n-slate-11"
                >
                  {{ t('PLAN_CATALOG.PER_MONTH') }}
                </span>
              </div>
              <div
                v-if="pricing(plan).monthly > 0"
                class="mt-1 text-xs text-n-slate-11"
              >
                {{
                  t('PLAN_CATALOG.ANNUAL_PRICE', {
                    price: money(pricing(plan).annual),
                  })
                }}
              </div>
            </td>
          </tr>
          <tr v-for="row in limitRows" :key="row.key">
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-normal dark:bg-n-solid-3"
            >
              {{ row.label }}
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              <template v-if="isIncluded(limitValue(plan, row.key))">
                {{ value(row.key, limitValue(plan, row.key)) }}
              </template>
              <span v-else class="inline-flex items-center justify-center">
                <span
                  class="i-lucide-x size-4 text-n-slate-8"
                  aria-hidden="true"
                />
                <span class="sr-only">{{
                  t('PLAN_CATALOG.NOT_INCLUDED')
                }}</span>
              </span>
            </td>
          </tr>
          <tr v-if="baseFeatureRows.length" data-testid="base-capabilities-row">
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-medium dark:bg-n-solid-3"
            >
              <div>{{ t('PLAN_CATALOG.BASE_FEATURES') }}</div>
              <ul
                class="m-0 mt-2 list-none space-y-1 p-0 text-xs font-normal text-n-slate-11"
              >
                <li v-for="feature in baseFeatureRows" :key="feature">
                  {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
                </li>
              </ul>
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              <span
                class="i-lucide-check size-4 text-n-slate-10"
                aria-hidden="true"
              />
              <span class="sr-only">{{ t('PLAN_CATALOG.INCLUDED') }}</span>
            </td>
          </tr>
          <tr
            v-for="feature in featureRows"
            :key="feature"
            :class="{ 'bg-n-blue-3': feature === requiredFeature }"
          >
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-normal dark:bg-n-solid-3"
            >
              <div
                :class="{
                  'rounded bg-n-blue-3 p-2 text-n-blue-12 font-medium':
                    feature === requiredFeature,
                }"
              >
                {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
              </div>
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              <span
                v-if="plan.feature_keys.includes(feature)"
                class="inline-flex items-center justify-center"
              >
                <span
                  class="i-lucide-check size-4 text-n-slate-10"
                  aria-hidden="true"
                />
                <span class="sr-only">{{ t('PLAN_CATALOG.INCLUDED') }}</span>
              </span>
              <span v-else class="inline-flex items-center justify-center">
                <span
                  class="i-lucide-x size-4 text-n-slate-8"
                  aria-hidden="true"
                />
                <span class="sr-only">{{
                  t('PLAN_CATALOG.NOT_INCLUDED')
                }}</span>
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="m-0 text-xs leading-5 text-n-slate-11">
      {{ t('PLAN_CATALOG.TABLE_NOTE') }}
    </p>
  </div>
</template>
