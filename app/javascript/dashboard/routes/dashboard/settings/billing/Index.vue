<script setup>
import { computed, onMounted, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { format } from 'date-fns';
import sessionStorage from 'shared/helpers/sessionStorage';

import BillingMeter from './components/BillingMeter.vue';
import BillingCard from './components/BillingCard.vue';
import BillingHeader from './components/BillingHeader.vue';
import DetailItem from './components/DetailItem.vue';
import PurchaseCreditsModal from './components/PurchaseCreditsModal.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';
import { getCurrencyConfig } from 'dashboard/constants/billing';
import { useI18n } from 'vue-i18n';

const { currentAccount, isOnChatwootCloud } = useAccount();
const {
  captainEnabled,
  captainLimits,
  responseLimits,
  storageLimits,
  fetchLimits,
  isFetchingLimits,
} = useCaptain();

const uiFlags = useMapGetter('accounts/getUIFlags');
const store = useStore();
const { t } = useI18n();

const BILLING_REFRESH_ATTEMPTED = 'billing_refresh_attempted';

// State for handling refresh attempts and loading
const isWaitingForBilling = ref(false);
const purchaseCreditsModalRef = ref(null);

// Currency selection shown to new accounts whose locale supports a non-USD currency.
const currencySelectionRequired = ref(false);
const currencyOptions = ref([]);

const customAttributes = computed(() => {
  return currentAccount.value.custom_attributes || {};
});

/**
 * Computed property for plan name
 * @returns {string|undefined}
 */
const planName = computed(() => {
  // For self-hosted, read from limits.plan
  if (!isOnChatwootCloud.value) {
    return currentAccount.value.limits?.plan?.name;
  }
  // For cloud, read from custom_attributes (existing behavior)
  return customAttributes.value.plan_name;
});

const canPurchaseCredits = computed(() => {
  const plan = planName.value?.toLowerCase();
  return plan && plan !== 'hacker';
});

/**
 * Computed property for subscribed quantity
 * @returns {number|undefined}
 */
const subscribedQuantity = computed(() => {
  // For self-hosted, this field may not be relevant
  if (!isOnChatwootCloud.value) {
    return undefined;
  }
  // For cloud, read from custom_attributes (existing behavior)
  return customAttributes.value.subscribed_quantity;
});

const billingCurrency = computed(() => {
  // For self-hosted, billing currency may not be relevant
  if (!isOnChatwootCloud.value) {
    return '';
  }
  // For cloud, read from custom_attributes (existing behavior)
  if (!customAttributes.value.billing_currency) return '';
  return t(
    getCurrencyConfig(customAttributes.value.billing_currency).i18nLabelKey
  );
});

const subscriptionRenewsOn = computed(() => {
  // For self-hosted, read from limits.plan
  if (!isOnChatwootCloud.value) {
    const planEnd = currentAccount.value.limits?.plan?.period_end;
    if (!planEnd) return '';
    const endDate = new Date(planEnd);
    // return date as 12 Jan, 2034
    return format(endDate, 'dd MMM, yyyy');
  }
  // For cloud, read from custom_attributes (existing behavior)
  if (!customAttributes.value.subscription_ends_on) return '';
  const endDate = new Date(customAttributes.value.subscription_ends_on);
  // return date as 12 Jan, 2034
  return format(endDate, 'dd MMM, yyyy');
});

// Set only while a cancellation is scheduled; the plan stays active until this date.
const subscriptionCancelsOn = computed(() => {
  if (!customAttributes.value.subscription_cancels_on) return '';
  const cancelDate = new Date(customAttributes.value.subscription_cancels_on);
  return format(cancelDate, 'dd MMM, yyyy');
});

/**
 * Computed property indicating if user has a billing plan
 * @returns {boolean}
 */
const hasABillingPlan = computed(() => {
  // For self-hosted, check if limits.plan exists
  if (!isOnChatwootCloud.value) {
    return !!currentAccount.value.limits?.plan;
  }
  // For cloud, check planName (existing behavior)
  return !!planName.value;
});

// Computed property for agents meter data
const agentsMeterData = computed(() => {
  const agents = currentAccount.value.limits?.agents;
  if (!agents) return null;
  return { consumed: agents.consumed ?? 0, totalCount: agents.allowed };
});

// Computed property for inboxes meter data
const inboxesMeterData = computed(() => {
  const inboxes = currentAccount.value.limits?.inboxes;
  if (!inboxes) return null;
  return { consumed: inboxes.consumed ?? 0, totalCount: inboxes.allowed };
});

const fetchAccountDetails = async () => {
  if (!hasABillingPlan.value) {
    const data = await store.dispatch('accounts/subscription');
    currencySelectionRequired.value = !!data?.currency_selection_required;
    currencyOptions.value = data?.currency_options || [];
  }
  // Always fetch limits for billing page to show credit usage
  fetchLimits();
};

const handleBillingPageLogic = async () => {
  // For self-hosted, just fetch limits and render
  if (!isOnChatwootCloud.value) {
    await fetchLimits();
    return;
  }

  // Check if we've already attempted a refresh for billing setup
  const billingRefreshAttempted = sessionStorage.get(BILLING_REFRESH_ATTEMPTED);

  // If cloud user, fetch account details first
  await fetchAccountDetails();

  // Waiting on the user to pick a billing currency — don't auto-refresh.
  if (currencySelectionRequired.value) return;

  // If still no billing plan after fetch
  if (!hasABillingPlan.value) {
    // If we haven't attempted refresh yet, do it once
    if (!billingRefreshAttempted) {
      isWaitingForBilling.value = true;
      sessionStorage.set(BILLING_REFRESH_ATTEMPTED, true);

      setTimeout(() => {
        window.location.reload();
      }, 5000);
    } else {
      // We've already tried refreshing, so just show the no billing message
      // Clear the flag for future visits
      sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
    }
  } else {
    // Billing plan found, clear any existing refresh flag
    sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
  }
};

const onSelectCurrency = async code => {
  await store.dispatch('accounts/selectBillingCurrency', code);
  currencySelectionRequired.value = false;
  // Currency stored and customer creation kicked off — resume the standard wait flow.
  await handleBillingPageLogic();
};

const onClickBillingPortal = () => {
  store.dispatch('accounts/checkout');
};

const onToggleChatWindow = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggle();
  }
};

const openPurchaseCreditsModal = () => {
  purchaseCreditsModalRef.value?.open();
};

const handleTopupSuccess = () => {
  // Refresh limits to show updated credit balance
  fetchLimits();
};

onMounted(handleBillingPageLogic);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetchingItem || isWaitingForBilling"
    :loading-message="
      isWaitingForBilling
        ? $t('BILLING_SETTINGS.NO_BILLING_USER')
        : $t('ATTRIBUTES_MGMT.LOADING')
    "
    :no-records-found="
      !hasABillingPlan && !isWaitingForBilling && !currencySelectionRequired
    "
    :no-records-message="
      isOnChatwootCloud
        ? $t('BILLING_SETTINGS.NO_BILLING_USER')
        : $t('BILLING_SETTINGS.NO_PLAN_ASSIGNED')
    "
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('BILLING_SETTINGS.TITLE')"
        :description="$t('BILLING_SETTINGS.DESCRIPTION')"
        :link-text="$t('BILLING_SETTINGS.VIEW_PRICING')"
        feature-name="billing"
      />
    </template>
    <template #body>
      <!-- Currency Selection Section (Cloud only) -->
      <section
        v-if="isOnChatwootCloud && currencySelectionRequired"
        class="grid gap-4"
      >
        <BillingCard
          :title="$t('BILLING_SETTINGS.CURRENCY.SELECT.TITLE')"
          :description="$t('BILLING_SETTINGS.CURRENCY.SELECT.DESCRIPTION')"
        >
          <template #action>
            <div class="flex gap-2">
              <ButtonV4
                v-for="code in currencyOptions"
                :key="code"
                sm
                solid
                blue
                :is-loading="uiFlags.isCheckoutInProcess"
                :disabled="uiFlags.isCheckoutInProcess"
                @click="onSelectCurrency(code)"
              >
                {{ $t(getCurrencyConfig(code).i18nLabelKey) }}
              </ButtonV4>
            </div>
          </template>
        </BillingCard>
      </section>

      <!-- Main Billing Section -->
      <section v-else class="grid gap-4">
        <!-- Subscription Management Section -->
        <BillingCard
          :title="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.TITLE')"
          :description="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.DESCRIPTION')"
        >
          <!-- Manage Subscription Button (Cloud only) -->
          <template #action>
            <ButtonV4
              v-if="isOnChatwootCloud"
              sm
              solid
              blue
              @click="onClickBillingPortal"
            >
              {{ $t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.BUTTON_TXT') }}
            </ButtonV4>
          </template>

          <!-- Plan Details -->
          <div
            v-if="planName || subscriptionRenewsOn"
            class="grid lg:grid-cols-4 sm:grid-cols-3 grid-cols-1 gap-2 divide-x divide-n-weak"
          >
            <DetailItem
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
              :value="planName"
            />
            <!-- Seat count (Cloud only) -->
            <DetailItem
              v-if="isOnChatwootCloud && subscribedQuantity"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.SEAT_COUNT')"
              :value="subscribedQuantity"
            />
            <DetailItem
              v-if="subscriptionCancelsOn"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.CANCELS_ON')"
              :value="subscriptionCancelsOn"
            />
            <DetailItem
              v-else-if="subscriptionRenewsOn"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.RENEWS_ON')"
              :value="subscriptionRenewsOn"
            />
            <!-- Currency (Cloud only) -->
            <DetailItem
              v-if="isOnChatwootCloud && billingCurrency"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.CURRENCY')"
              :value="billingCurrency"
            />
          </div>
        </BillingCard>

        <!-- Captain Section -->
        <BillingCard
          v-if="captainEnabled"
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.DESCRIPTION')"
        >
          <template #action>
            <div class="flex gap-2">
              <!-- Refresh Credits Button (Cloud only) -->
              <ButtonV4
                v-if="isOnChatwootCloud"
                sm
                flushed
                slate
                icon="i-lucide-refresh-cw"
                :is-loading="isFetchingLimits"
                @click="fetchLimits"
              >
                {{ $t('BILLING_SETTINGS.CAPTAIN.REFRESH_CREDITS') }}
              </ButtonV4>
              <!-- Buy Credits Button -->
              <ButtonV4
                v-if="canPurchaseCredits"
                sm
                solid
                blue
                @click="openPurchaseCreditsModal"
              >
                {{ $t('BILLING_SETTINGS.TOPUP.BUY_CREDITS') }}
              </ButtonV4>
            </div>
          </template>

          <!-- Captain Usage Section -->
          <div v-if="captainLimits" class="space-y-4">
            <div class="grid lg:grid-cols-2 gap-4">
              <BillingMeter
                v-if="responseLimits"
                :title="$t('BILLING_SETTINGS.CAPTAIN.RESPONSES_CUSTOMER')"
                :consumed="responseLimits.customerConsumed"
                :total-count="responseLimits.customerTotalCount"
              />
              <BillingMeter
                v-if="responseLimits"
                :title="$t('BILLING_SETTINGS.CAPTAIN.RESPONSES_COPILOT')"
                :consumed="responseLimits.copilotConsumed"
                :total-count="responseLimits.copilotTotalCount"
              />
            </div>

            <div class="grid lg:grid-cols-2 gap-4">
              <BillingMeter
                v-if="captainLimits && storageLimits"
                :title="$t('BILLING_SETTINGS.CAPTAIN.STORAGE')"
                v-bind="storageLimits"
                unit="bytes"
              />
            </div>
          </div>

          <!-- Account Usage Section -->
          <div v-if="agentsMeterData || inboxesMeterData" class="space-y-4">
            <div class="grid lg:grid-cols-2 gap-4">
              <BillingMeter
                v-if="agentsMeterData"
                :title="$t('BILLING_SETTINGS.CAPTAIN.AGENTS')"
                v-bind="agentsMeterData"
              />
              <BillingMeter
                v-if="inboxesMeterData"
                :title="$t('BILLING_SETTINGS.CAPTAIN.INBOXES')"
                v-bind="inboxesMeterData"
              />
            </div>
          </div>
        </BillingCard>

        <!-- Captain Upgrade Prompt (when not enabled) -->
        <BillingCard
          v-else
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.UPGRADE')"
        >
          <template #action>
            <ButtonV4
              v-if="isOnChatwootCloud"
              sm
              solid
              slate
              @click="onClickBillingPortal"
            >
              {{ $t('CAPTAIN.PAYWALL.UPGRADE_NOW') }}
            </ButtonV4>
          </template>
        </BillingCard>

        <BillingHeader
          class="px-1 mt-5"
          :title="$t('BILLING_SETTINGS.CHAT_WITH_US.TITLE')"
          :description="$t('BILLING_SETTINGS.CHAT_WITH_US.DESCRIPTION')"
        >
          <ButtonV4
            sm
            solid
            slate
            icon="i-lucide-life-buoy"
            @click="onToggleChatWindow"
          >
            {{ $t('BILLING_SETTINGS.CHAT_WITH_US.BUTTON_TXT') }}
          </ButtonV4>
        </BillingHeader>
      </section>
      <PurchaseCreditsModal
        ref="purchaseCreditsModalRef"
        @success="handleTopupSuccess"
      />
    </template>
  </SettingsLayout>
</template>
