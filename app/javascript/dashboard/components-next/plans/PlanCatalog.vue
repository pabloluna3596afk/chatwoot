<script setup>
/* Catalog fields and repeated copy use translation keys derived at runtime. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePlanCatalog } from 'dashboard/composables/usePlanCatalog';
import Button from 'next/button/Button.vue';
import PlanCard from './PlanCard.vue';
import PlanComparisonTable from './PlanComparisonTable.vue';
import {
  matchesPlan,
  planViewProps,
  usePlanPresentation,
} from './planPresentation';

const props = defineProps({
  ...planViewProps,
  simple: { type: Boolean, default: false },
});
const emit = defineEmits(['select', 'requestUpgrade', 'continue']);
const { t } = useI18n();
const { plans, status, retry } = usePlanCatalog();
const { baseFeatures } = usePlanPresentation();
const baseFeatureKeys = computed(() => baseFeatures(plans.value));
const currentPlan = computed(() =>
  plans.value.find(plan => matchesPlan(plan, props.currentPlanId))
);
const hasCurrentPlan = computed(() => props.currentPlanId !== null);
</script>

<template>
  <div class="space-y-6" :aria-busy="status === 'loading'">
    <div
      v-if="status === 'loading' || status === 'idle'"
      role="status"
      :aria-label="t('PLAN_CATALOG.LOADING')"
      class="grid gap-4 sm:grid-cols-2"
      data-testid="plans-loading"
    >
      <span class="sr-only">{{ t('PLAN_CATALOG.LOADING') }}</span>
      <div
        v-for="item in 2"
        :key="item"
        class="h-64 rounded-2xl bg-n-slate-3 motion-safe:animate-pulse"
        aria-hidden="true"
      />
    </div>
    <div
      v-else-if="status === 'error'"
      role="alert"
      class="space-y-4 rounded-xl border border-n-weak bg-n-solid-1 p-6 dark:bg-n-solid-3"
    >
      <p class="m-0 text-n-slate-12">{{ t('PLAN_CATALOG.ERROR') }}</p>
      <Button
        :label="t('PLAN_CATALOG.RETRY')"
        variant="outline"
        @click="retry"
      />
    </div>
    <p
      v-else-if="!plans.length"
      role="status"
      class="rounded-xl bg-n-slate-3 p-6 text-n-slate-11"
    >
      {{ t('PLAN_CATALOG.EMPTY') }}
    </p>
    <template v-else>
      <section
        v-if="baseFeatureKeys.length"
        class="space-y-4 rounded-2xl border border-n-weak bg-n-slate-2 p-5"
        data-testid="catalog-base-capabilities"
      >
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('PLAN_CATALOG.BASE_FEATURES') }}
        </h2>
        <ul
          class="m-0 grid list-none gap-2 p-0 text-sm sm:grid-cols-2 xl:grid-cols-4"
        >
          <li
            v-for="feature in baseFeatureKeys"
            :key="feature"
            class="rounded-lg bg-n-solid-1 px-3 py-2 text-n-slate-12 dark:bg-n-solid-3"
          >
            {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
          </li>
        </ul>
      </section>
      <p
        v-if="!currentPlan"
        role="status"
        class="rounded-xl bg-n-slate-3 p-4 text-sm text-n-slate-11"
      >
        {{
          t(
            hasCurrentPlan ? 'PLAN_CATALOG.UNLISTED' : 'PLAN_CATALOG.NO_CURRENT'
          )
        }}
      </p>
      <template v-if="simple">
        <h2 v-if="currentPlan" class="m-0 text-heading-1">
          {{ t('PLAN_CATALOG.HEADING', { plan: currentPlan.name }) }}
        </h2>
        <PlanCard
          v-if="currentPlan"
          v-bind="props"
          :plan="currentPlan"
          compact
        />
        <slot name="actions" :current-plan="currentPlan" />
      </template>
      <template v-else>
        <div
          class="flex snap-x snap-mandatory gap-4 overflow-x-auto p-1 pb-4"
          :aria-label="t('PLAN_CATALOG.COMPARE')"
        >
          <PlanCard
            v-for="plan in plans"
            :key="plan.id"
            v-bind="props"
            :plan="plan"
            :plans="plans"
            class="w-[min(85vw,17rem)] shrink-0 snap-start xl:w-auto xl:min-w-52 xl:flex-1"
            @select="emit('select', $event)"
            @request-upgrade="emit('requestUpgrade', $event)"
            @continue="emit('continue', $event)"
          />
        </div>
        <p class="text-xs leading-5 text-n-slate-11">
          {{ t('PLAN_CATALOG.CONFIGURATION') }}
        </p>
        <section class="space-y-6 pt-8">
          <h2 class="m-0 text-heading-1">{{ t('PLAN_CATALOG.DETAIL') }}</h2>
          <PlanComparisonTable v-bind="props" :plans="plans" />
        </section>
      </template>
    </template>
  </div>
</template>
