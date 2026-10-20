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
  compact: { type: Boolean, default: false },
});
// Reserved for the checkout PR; paid plans have no active action today.
// eslint-disable-next-line vue/no-unused-emit-declarations
const emit = defineEmits(['select', 'requestUpgrade', 'continue']);
const { t } = useI18n();
const { summary } = usePlanPresentation();
const current = computed(() => matchesPlan(props.plan, props.currentPlanId));
const selected = computed(() => matchesPlan(props.plan, props.selectedPlanId));
const selectable = computed(
  () => props.canSelect && current.value && props.plan.state === 'available'
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
      current || selected
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
    <span
      :class="current ? 'i-lucide-sprout' : 'i-lucide-layers'"
      class="size-7 text-n-blue-11"
      aria-hidden="true"
    />
    <div>
      <h3 class="m-0 break-words text-heading-2">{{ plan.name }}</h3>
      <p
        v-if="plan.description"
        class="mb-0 mt-3 text-sm leading-6 text-n-slate-11"
      >
        {{ plan.description }}
      </p>
    </div>
    <ul
      class="m-0 flex-1 list-none space-y-4 border-t border-n-weak p-0 pt-5 text-sm"
    >
      <li
        v-for="field in summary(plan)"
        :key="field.key"
        class="flex items-start gap-2"
      >
        <span
          :class="field.icon"
          class="mt-0.5 size-4 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        {{ field.text }}
      </li>
    </ul>
    <ul
      v-if="!compact && plan.feature_keys.length"
      class="m-0 list-none space-y-3 border-t border-n-weak p-0 pt-4 text-sm"
    >
      <li
        v-for="feature in plan.feature_keys"
        :key="feature"
        class="flex gap-2"
      >
        <span
          :class="
            feature === 'captain_integration'
              ? 'i-woot-captain'
              : 'i-lucide-check'
          "
          class="size-4 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        {{ t(`PLAN_CATALOG.FEATURES.${feature}`) }}
      </li>
    </ul>
    <Button
      v-if="!compact"
      :disabled="!selectable"
      :variant="selectable ? 'solid' : 'outline'"
      color="blue"
      class="!h-auto !min-h-12 w-full !whitespace-normal py-3"
      :class="selectable ? '!bg-n-blue-11 !text-n-solid-1' : ''"
      @click="choose"
    >
      {{
        selectable
          ? t('PLAN_CATALOG.CONTINUE', { plan: plan.name })
          : t(`PLAN_CATALOG.STATES.${plan.state}`)
      }}
    </Button>
  </article>
</template>
