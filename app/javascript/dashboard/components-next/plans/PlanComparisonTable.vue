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
const { rows, features, value } = usePlanPresentation();
const limitRows = computed(() => rows(props.plans));
const featureRows = computed(() => features(props.plans));
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
              :class="{ '!bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
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
          <tr v-for="row in limitRows" :key="row.key">
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-normal dark:bg-n-solid-3"
            >
              <div class="flex items-center gap-2">
                <div
                  :class="row.icon"
                  class="size-4 shrink-0"
                  aria-hidden="true"
                />
                {{ row.label }}
              </div>
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              {{ value(row.key, plan.limits[row.key]) }}
            </td>
          </tr>
          <tr v-for="feature in featureRows" :key="feature">
            <th
              scope="row"
              class="sticky start-0 z-10 border-b border-n-weak bg-n-solid-1 p-4 text-start font-normal dark:bg-n-solid-3"
            >
              {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
            </th>
            <td
              v-for="plan in plans"
              :key="plan.id"
              class="border-b border-n-weak p-4 text-center"
              :class="{ 'bg-n-blue-3': matchesPlan(plan, currentPlanId) }"
            >
              <div
                v-if="plan.feature_keys.includes(feature)"
                class="i-lucide-check inline-block size-5 text-n-blue-11"
                aria-hidden="true"
              />
              <div
                :class="plan.feature_keys.includes(feature) ? 'sr-only' : ''"
              >
                {{
                  t(
                    plan.feature_keys.includes(feature)
                      ? 'PLAN_CATALOG.INCLUDED'
                      : 'PLAN_CATALOG.UNKNOWN'
                  )
                }}
              </div>
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
