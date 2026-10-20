<script setup>
import { computed, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'next/button/Button.vue';
import PlanPricingView from './PlanPricingView.vue';

defineProps({ requiredFeature: { type: String, default: '' } });
defineOptions({ inheritAttrs: false });
const { currentAccount, isOnChatwootCloud } = useAccount();
const { isAdmin } = useAdmin();
const comparing = ref(false);
const canCompare = computed(
  () =>
    isAdmin.value &&
    !isOnChatwootCloud.value &&
    currentAccount.value?.billing_provider !== 'shopify'
);
const currentPlanId = computed(
  () =>
    currentAccount.value?.limits?.plan?.id ??
    currentAccount.value?.limits?.plan?.slug ??
    null
);
</script>

<template>
  <template v-if="canCompare">
    <Button
      v-bind="$attrs"
      :label="$t('PLAN_CATALOG.COMPARE')"
      variant="outline"
      color="slate"
      class="!h-auto !min-h-11 !whitespace-normal"
      @click="comparing = true"
    />
    <PlanPricingView
      v-if="comparing"
      context="upgrade"
      :current-plan-id="currentPlanId"
      :required-feature="requiredFeature"
      @close="comparing = false"
    />
  </template>
  <template v-else />
</template>
