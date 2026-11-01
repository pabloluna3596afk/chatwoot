<script setup>
import { onMounted, computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useRouter } from 'vue-router';

import Banner from 'dashboard/components-next/banner/Banner.vue';
import PlanCompareButton from 'next/plans/PlanCompareButton.vue';

const router = useRouter();
const { accountId, currentAccount, isOnChatwootCloud } = useAccount();
const { isAdmin } = useAdmin();
const usesProviderBilling = computed(
  () =>
    isOnChatwootCloud.value ||
    currentAccount.value?.billing_provider === 'shopify'
);
const canOpenBilling = computed(
  () => usesProviderBilling.value || isAdmin.value
);

const { responseLimits, fetchLimits } = useCaptain();

const openBilling = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};

const showBanner = computed(() => {
  if (!responseLimits.value) return false;

  const { consumed, totalCount } = responseLimits.value;
  if (!consumed || !totalCount) return false;

  return consumed / totalCount > 0.8;
});

onMounted(fetchLimits);
</script>

<template>
  <Banner
    v-show="showBanner"
    color="amber"
    :class="{ '!text-n-amber-12': !usesProviderBilling }"
    :action-label="
      canOpenBilling ? $t('CAPTAIN.PAYWALL.UPGRADE_NOW') : null
    "
    @action="openBilling"
  >
    {{ $t('CAPTAIN.BANNER.RESPONSES') }}
    <PlanCompareButton class="mt-2" />
  </Banner>
</template>
