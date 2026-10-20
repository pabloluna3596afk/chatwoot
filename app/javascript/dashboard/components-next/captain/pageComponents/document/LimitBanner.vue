<script setup>
import { onMounted, computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useRouter } from 'vue-router';

import Banner from 'dashboard/components-next/banner/Banner.vue';
import PlanCompareButton from 'next/plans/PlanCompareButton.vue';

const router = useRouter();
const { accountId, currentAccount, isOnChatwootCloud } = useAccount();
const usesProviderBilling = computed(
  () =>
    isOnChatwootCloud.value ||
    currentAccount.value?.billing_provider === 'shopify'
);

const { documentLimits, fetchLimits } = useCaptain();

const openBilling = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};

const showBanner = computed(() => {
  if (!documentLimits.value) return false;

  const { currentAvailable } = documentLimits.value;
  return currentAvailable === 0;
});

onMounted(fetchLimits);
</script>

<template>
  <Banner
    v-show="showBanner"
    color="amber"
    :class="{ '!text-n-amber-12': !usesProviderBilling }"
    :action-label="
      usesProviderBilling ? $t('CAPTAIN.PAYWALL.UPGRADE_NOW') : null
    "
    @action="openBilling"
  >
    {{ $t('CAPTAIN.BANNER.DOCUMENTS') }}
    <PlanCompareButton class="mt-2" />
  </Banner>
</template>
