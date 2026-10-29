<script setup>
/* Catalog fields and repeated copy use translation keys derived at runtime. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import {
  matchesPlan,
  planViewProps,
  usePlanPresentation,
} from './planPresentation';

const props = defineProps({
  ...planViewProps,
  plan: { type: Object, required: true },
  plans: { type: Array, default: () => [] },
  compact: { type: Boolean, default: false },
});
// eslint-disable-next-line vue/no-unused-emit-declarations
const emit = defineEmits(['select', 'requestUpgrade', 'continue']);
const { t } = useI18n();
const { featureChanges, money, pricing, summary } = usePlanPresentation();
const current = computed(() => matchesPlan(props.plan, props.currentPlanId));
const selected = computed(() => matchesPlan(props.plan, props.selectedPlanId));
const changes = computed(() =>
  featureChanges(props.plans.length ? props.plans : [props.plan], props.plan)
);
const prices = computed(() => pricing(props.plan));
const selectable = computed(
  () =>
    props.canSelect &&
    (props.canPurchase || current.value) &&
    props.plan.state === 'available'
);
const choose = () => {
  if (!selectable.value) return;
  emit('select', props.plan.id);
  emit('continue', props.plan.id);
};
</script>

<template>
  <article
    class="flex min-w-0 flex-col gap-5 rounded-2xl border bg-n-solid-1 p-5 text-n-slate-12 dark:bg-n-solid-3"
    :class="
      current ||
      selected ||
      (requiredFeature && plan.feature_keys.includes(requiredFeature))
        ? 'border-n-blue-9 ring-1 ring-n-blue-9'
        : 'border-n-weak'
    "
    :data-plan-id="plan.id"
  >
    <div class="flex items-center justify-between gap-2 text-xs text-n-blue-11">
      <span class="rounded-full bg-n-blue-3 px-3 py-1 text-n-blue-12">{{
        current
          ? t('PLAN_CATALOG.CURRENT')
          : t(`PLAN_CATALOG.STATES.${plan.state}`)
      }}</span>
      <span
        v-if="current"
        class="i-lucide-circle-check size-5"
        aria-hidden="true"
      />
    </div>
    <div>
      <h3 class="m-0 break-words text-heading-2">{{ plan.name }}</h3>
      <p
        v-if="plan.description"
        class="mb-0 mt-3 text-sm leading-6 text-n-slate-11"
      >
        {{ plan.description }}
      </p>
    </div>
    <div class="space-y-1 border-b border-n-weak pb-4">
      <p class="m-0 text-2xl font-semibold text-n-slate-12">
        {{
          prices.monthly === 0 ? t('PLAN_CATALOG.FREE') : money(prices.monthly)
        }}
        <span
          v-if="prices.monthly > 0"
          class="text-sm font-normal text-n-slate-11"
        >
          {{ t('PLAN_CATALOG.PER_MONTH') }}
        </span>
      </p>
      <p v-if="prices.monthly > 0" class="m-0 text-xs text-n-slate-11">
        {{ t('PLAN_CATALOG.ANNUAL_PRICE', { price: money(prices.annual) }) }}
      </p>
    </div>
    <ul
      v-if="compact && summary(plan).length"
      class="m-0 flex-1 list-none space-y-2 p-0 text-sm"
    >
      <li v-for="field in summary(plan)" :key="field.key">
        {{ field.text }}
      </li>
    </ul>
    <ul v-if="!compact" class="m-0 flex-1 list-none space-y-3 p-0 text-sm">
      <li
        v-if="
          changes.previousPlan &&
          (changes.added.length || changes.removed.length)
        "
        class="font-medium text-n-slate-12"
      >
        {{ t('PLAN_CATALOG.INHERITS', { plan: changes.previousPlan.name }) }}
      </li>
      <li
        v-for="feature in changes.added"
        :key="feature"
        class="flex items-start gap-2"
        :class="{
          'rounded bg-n-blue-3 p-2 text-n-blue-12': feature === requiredFeature,
        }"
      >
        <span
          class="i-lucide-check mt-0.5 size-4 shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
      </li>
      <li v-if="changes.removed.length" class="space-y-1 text-n-slate-11">
        <span>{{ t('PLAN_CATALOG.REMOVED_FEATURES') }}</span>
        <ul class="m-0 list-none space-y-1 p-0">
          <li v-for="feature in changes.removed" :key="feature">
            {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
          </li>
        </ul>
      </li>
    </ul>
    <Button
      v-if="!compact"
      :disabled="!selectable"
      :variant="selectable ? 'solid' : 'outline'"
      color="blue"
      size="sm"
      class="!h-auto !min-h-10 w-full !whitespace-normal py-2"
      :class="selectable ? '!bg-n-blue-11 !text-n-solid-1' : ''"
      @click="choose"
    >
      {{
        selectable
          ? t(
              current
                ? 'PLAN_CATALOG.CONTINUE'
                : 'PLAN_CATALOG.STATES.available',
              { plan: plan.name }
            )
          : t(
              current
                ? 'PLAN_CATALOG.CURRENT'
                : `PLAN_CATALOG.STATES.${plan.state}`
            )
      }}
    </Button>
  </article>
</template>
