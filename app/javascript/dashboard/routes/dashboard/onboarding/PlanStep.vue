<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import PlanCatalog from 'next/plans/PlanCatalog.vue';
import PlanPricingView from 'next/plans/PlanPricingView.vue';
import Button from 'next/button/Button.vue';

const props = defineProps({ busy: { type: Boolean, default: false } });
const emit = defineEmits(['continue']);
const { t } = useI18n();
const { currentAccount } = useAccount();
const store = useStore();
const comparing = ref(false);
const currentPlanId = computed(
  () =>
    currentAccount.value?.limits?.plan?.id ??
    currentAccount.value?.limits?.plan?.slug ??
    null
);
onMounted(() => {
  if (!currentAccount.value?.limits) store.dispatch('accounts/limits');
});
</script>

<template>
  <section
    class="mx-auto w-full max-w-lg space-y-6"
    data-testid="onboarding-plan"
  >
    <PlanCatalog
      context="onboarding"
      :current-plan-id="currentPlanId"
      :selected-plan-id="currentPlanId"
      can-select
      simple
    >
      <template #actions="{ currentPlan }">
        <p v-if="currentPlan" class="m-0 text-sm leading-6 text-n-slate-11">
          {{ t('PLAN_CATALOG.SUPPORT') }}
        </p>
        <Button
          v-if="currentPlan"
          :disabled="props.busy || currentPlan.state !== 'available'"
          :is-loading="props.busy"
          class="!min-h-12 w-full !bg-n-blue-11 !text-n-solid-1"
          :label="t('PLAN_CATALOG.CONTINUE', { plan: currentPlan.name })"
          data-testid="finish"
          @click="emit('continue')"
        />
        <Button
          :label="t('PLAN_CATALOG.COMPARE')"
          variant="outline"
          color="slate"
          class="!min-h-12 w-full"
          @click="comparing = true"
        />
      </template>
    </PlanCatalog>
    <PlanPricingView
      v-if="comparing"
      context="onboarding"
      :current-plan-id="currentPlanId"
      :selected-plan-id="currentPlanId"
      can-select
      @close="comparing = false"
    />
  </section>
</template>
