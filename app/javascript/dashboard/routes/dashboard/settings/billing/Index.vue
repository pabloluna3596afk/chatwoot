<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import sessionStorage from 'shared/helpers/sessionStorage';

import BillingCard from './components/BillingCard.vue';
import BillingHeader from './components/BillingHeader.vue';
import DetailItem from './components/DetailItem.vue';
import PurchaseCreditsModal from './components/PurchaseCreditsModal.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';
import PlanPricingView from 'next/plans/PlanPricingView.vue';
import { getCurrencyConfig } from 'dashboard/constants/billing';
import { useI18n } from 'vue-i18n';
import PayphonePaymentsAPI from 'dashboard/api/payphonePayments';
import { shouldShowPayphoneRenewalDate } from './payphoneBilling';
import BillingTabs from './components/BillingTabs.vue';
import UsageDashboard from './UsageDashboard.vue';
import { formatBillingDate } from './billingDate';

const { currentAccount, isOnChatwootCloud } = useAccount();
const {
  captainEnabled,
  responseLimits,
  copilotLimits,
  internalLimits,
  storageLimits,
  fetchLimits,
  isFetchingLimits,
} = useCaptain();

const uiFlags = useMapGetter('accounts/getUIFlags');
const store = useStore();
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const activeTab = computed(() =>
  route.query.tab === 'facturacion' ? 'facturacion' : 'uso'
);
const hasOpenedBilling = ref(false);
watch(
  activeTab,
  tab => {
    if (tab === 'facturacion') hasOpenedBilling.value = true;
  },
  { immediate: true }
);

const BILLING_REFRESH_ATTEMPTED = 'billing_refresh_attempted';

// State for handling refresh attempts and loading
const isWaitingForBilling = ref(false);
const purchaseCreditsModalRef = ref(null);
const comparingPlans = ref(false);
const payphoneEnabled = ref(false);
const payphoneHistory = ref([]);
const isLoadingPayphone = ref(true);
const payphoneLoadFailed = ref(false);
const payphoneRenewalState = ref(null);
const payphonePeriodEnd = ref(null);
const payphoneGraceEnd = ref(null);
const showPayphoneRenewalDate = computed(() =>
  shouldShowPayphoneRenewalDate(payphoneRenewalState.value)
);
const latestApprovedPayphonePayment = computed(() =>
  payphoneHistory.value.find(payment => payment.status === 'approved')
);
const payphonePlanId = ref(null);
const payphoneQuote = ref(null);
const payphoneNeedsInvoice = ref(false);
const payphoneInvoice = ref({
  billing_tax_id_type: 'cedula',
  billing_tax_id: '',
  billing_name: '',
  billing_email: '',
  billing_phone: '',
  billing_address: '',
});
const payphonePayment = ref(null);
const payphoneError = ref('');
const payphoneStatus = ref(
  new URLSearchParams(window.location.search).get('payphone') || ''
);
const payphoneBusy = ref(false);
const currentPlanId = computed(
  () =>
    currentAccount.value.limits?.plan?.id ??
    currentAccount.value.limits?.plan?.slug ??
    null
);

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
    const planEnd =
      payphonePeriodEnd.value || currentAccount.value.limits?.plan?.period_end;
    if (!planEnd) return '';
    return formatBillingDate(planEnd, locale.value);
  }
  // For cloud, read from custom_attributes (existing behavior)
  if (!customAttributes.value.subscription_ends_on) return '';
  return formatBillingDate(
    customAttributes.value.subscription_ends_on,
    locale.value
  );
});

// Set only while a cancellation is scheduled; the plan stays active until this date.
const subscriptionCancelsOn = computed(() => {
  if (!customAttributes.value.subscription_cancels_on) return '';
  return formatBillingDate(
    customAttributes.value.subscription_cancels_on,
    locale.value
  );
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

const captainPeriodEnd = computed(
  () => currentAccount.value.limits?.plan?.period_end || null
);

const agentsMeterData = computed(() => {
  const agents = currentAccount.value.limits?.agents;
  return agents
    ? { consumed: agents.consumed ?? 0, totalCount: agents.allowed }
    : null;
});
const inboxesMeterData = computed(() => {
  const inboxes = currentAccount.value.limits?.inboxes;
  return inboxes
    ? { consumed: inboxes.consumed ?? 0, totalCount: inboxes.allowed }
    : null;
});

const fetchAccountDetails = async () => {
  if (!hasABillingPlan.value) {
    const data = await store.dispatch('accounts/subscription');
    currencySelectionRequired.value = !!data?.currency_selection_required;
    currencyOptions.value = data?.currency_options || [];
    if (currencySelectionRequired.value) {
      await router.replace({ query: { ...route.query, tab: 'facturacion' } });
    }
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

const loadPayphone = async () => {
  if (isOnChatwootCloud.value) return;
  isLoadingPayphone.value = true;
  payphoneLoadFailed.value = false;
  try {
    const { data } = await PayphonePaymentsAPI.get();
    payphoneEnabled.value = data.enabled;
    payphoneHistory.value = data.payments;
    payphoneRenewalState.value = data.renewal_state;
    payphonePeriodEnd.value = data.period_end;
    payphoneGraceEnd.value = data.grace_end;
  } catch {
    payphoneEnabled.value = false;
    payphoneLoadFailed.value = true;
  } finally {
    isLoadingPayphone.value = false;
  }
};

async function quotePayphone() {
  if (!payphonePlanId.value) return;
  try {
    const { data } = await PayphonePaymentsAPI.quote({
      plan_id: payphonePlanId.value,
      needs_invoice: payphoneNeedsInvoice.value,
    });
    payphoneQuote.value = data;
  } catch (error) {
    payphoneError.value = error.response?.data?.error || t('PAYPHONE.ERROR');
  }
}

const selectPayphonePlan = async planId => {
  payphonePlanId.value = planId;
  payphoneNeedsInvoice.value = false;
  payphoneError.value = '';
  comparingPlans.value = false;
  await router.replace({ query: { ...route.query, tab: 'facturacion' } });
  await quotePayphone();
};

const beginPayphonePayment = async () => {
  payphoneBusy.value = true;
  payphoneError.value = '';
  try {
    const { data } = await PayphonePaymentsAPI.create({
      plan_id: payphonePlanId.value,
      needs_invoice: payphoneNeedsInvoice.value,
      ...payphoneInvoice.value,
    });
    payphonePayment.value = data;
    payphoneStatus.value = 'pending';
    payphoneQuote.value = { ...payphoneQuote.value, amount: data.amount };
    if (data.box.preview) return;
    if (!document.getElementById('payphone-sdk')) {
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href =
        'https://cdn.payphonetodoesposible.com/box/v2.0/payphone-payment-box.css';
      document.head.appendChild(css);
      const script = document.createElement('script');
      script.id = 'payphone-sdk';
      script.type = 'module';
      script.src =
        'https://cdn.payphonetodoesposible.com/box/v2.0/payphone-payment-box.js';
      document.head.appendChild(script);
      await new Promise((resolve, reject) => {
        script.onload = resolve;
        script.onerror = reject;
      });
    }
    new window.PPaymentButtonBox(data.box).render('payphone-box');
  } catch (error) {
    payphoneError.value = error.response?.data?.error || t('PAYPHONE.ERROR');
  } finally {
    payphoneBusy.value = false;
  }
};

const previewPayphone = async status => {
  payphoneBusy.value = true;
  try {
    const { data } = await PayphonePaymentsAPI.previewConfirm(
      payphonePayment.value.id,
      status
    );
    payphonePayment.value = { ...payphonePayment.value, ...data };
    payphoneStatus.value = data.status || 'verifying';
    await loadPayphone();
    if (data.status === 'approved') {
      payphonePlanId.value = null;
      payphonePayment.value = null;
      payphoneQuote.value = null;
      await fetchLimits();
    }
    if (['cancelled', 'failed'].includes(data.status))
      payphonePayment.value = null;
  } catch (error) {
    payphoneStatus.value = 'verifying';
  } finally {
    payphoneBusy.value = false;
  }
};

const formatPayphoneAmount = (cents, currency) =>
  new Intl.NumberFormat(locale.value, { style: 'currency', currency }).format(
    cents / 100
  );

const formattedPayphoneDate = value =>
  value ? formatBillingDate(value, locale.value) : '';

const payphoneRenewalMessage = () => {
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(`PAYPHONE.RENEWAL.${payphoneRenewalState.value}`, {
    date: formattedPayphoneDate(payphonePeriodEnd.value),
    grace_end: formattedPayphoneDate(payphoneGraceEnd.value),
  });
};
const usageRenewalLabel = computed(() => {
  if (['grace', 'expired'].includes(payphoneRenewalState.value)) {
    return t('BILLING_SETTINGS.USAGE.EXPIRED_ON', {
      date: formattedPayphoneDate(payphonePeriodEnd.value),
    });
  }
  if (subscriptionRenewsOn.value) {
    return `${t('BILLING_SETTINGS.CURRENT_PLAN.RENEWS_ON')} ${subscriptionRenewsOn.value}`;
  }
  return t('BILLING_SETTINGS.USAGE.FREE_PLAN');
});
const usagePlanStatus = computed(() => {
  const state = payphoneRenewalState.value;
  if (state === 'grace') return t('BILLING_SETTINGS.USAGE.STATUS.GRACE');
  if (state === 'expired' || !planName.value)
    return t('BILLING_SETTINGS.USAGE.STATUS.FREE');
  return t('BILLING_SETTINGS.USAGE.STATUS.ACTIVE');
});
const expiredUsageMessage = computed(() => {
  if (payphoneRenewalState.value === 'expired') {
    return t('BILLING_SETTINGS.USAGE.EXPIRED_BANNER', {
      date: formattedPayphoneDate(payphonePeriodEnd.value),
    });
  }
  if (payphoneRenewalState.value === 'grace') return payphoneRenewalMessage();
  return '';
});

onMounted(async () => {
  await handleBillingPageLogic();
  await loadPayphone();
});
</script>

<template>
  <SettingsLayout
    class="min-w-0"
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
        :link-text="
          isOnChatwootCloud ? $t('BILLING_SETTINGS.VIEW_PRICING') : ''
        "
        feature-name="billing"
      >
        <template v-if="hasABillingPlan || currencySelectionRequired" #tabs>
          <BillingTabs />
        </template>
        <template
          v-if="
            !isOnChatwootCloud &&
            (activeTab === 'facturacion' || !hasABillingPlan)
          "
          #actions
        >
          <ButtonV4
            :label="t('PLAN_CATALOG.COMPARE')"
            intent="secondary"
            @click="comparingPlans = true"
          />
        </template>
      </BaseSettingsHeader>
      <PlanPricingView
        v-if="comparingPlans"
        context="billing"
        :current-plan-id="currentPlanId"
        :can-select="payphoneEnabled"
        :can-purchase="payphoneEnabled"
        @select="selectPayphonePlan"
        @close="comparingPlans = false"
      />
    </template>
    <template #body>
      <UsageDashboard
        v-if="activeTab === 'uso'"
        :plan-name="planName"
        :plan-status="usagePlanStatus"
        :is-loading-limits="isFetchingLimits"
        :renewal-date="usageRenewalLabel"
        :period-end="captainPeriodEnd"
        :response-limits="responseLimits"
        :copilot-limits="copilotLimits"
        :internal-limits="internalLimits"
        :storage-limits="storageLimits"
        :agents-meter-data="agentsMeterData"
        :inboxes-meter-data="inboxesMeterData"
        :expired-message="expiredUsageMessage"
        @compare-plans="comparingPlans = true"
        @billing="
          router.replace({ query: { ...route.query, tab: 'facturacion' } })
        "
      />
      <!-- prettier-ignore -->
      <div v-if="hasOpenedBilling" v-show="activeTab === 'facturacion'" id="billing-panel-facturacion" role="tabpanel" aria-labelledby="billing-tab-facturacion">
      <div
        v-if="payphoneEnabled && payphoneRenewalState"
        role="status"
        class="mb-4 flex flex-col gap-3 rounded-xl border border-n-weak bg-n-slate-2 p-4 text-sm sm:flex-row sm:items-center sm:justify-between dark:bg-n-solid-3"
      >
        <span>{{ payphoneRenewalMessage() }}</span>
        <ButtonV4
          :label="t('PAYPHONE.RENEW')"
          variant="outline"
          sm
          @click="comparingPlans = true"
        />
      </div>
      <div
        v-if="payphoneStatus"
        role="status"
        class="mb-4 rounded-xl border border-n-weak bg-n-slate-2 p-4 text-sm"
      >
        <template v-if="['pending', 'verifying'].includes(payphoneStatus)">
          <span
            class="i-lucide-loader-circle me-2 inline-block size-4 animate-spin"
            aria-hidden="true"
          />
          {{ t('PAYPHONE.VERIFYING') }}
        </template>
        <template v-else-if="payphoneStatus === 'approved'">
          {{ t('PAYPHONE.APPROVED') }}
          {{ formattedPayphoneDate(latestApprovedPayphonePayment?.period_end) }}
          <a
            v-if="payphoneHistory.length"
            href="#payphone-history"
            class="ms-2 text-n-blue-11 underline"
          >
            {{ t('PAYPHONE.HISTORY_LINK') }}
          </a>
        </template>
        <template v-else-if="['cancelled', 'failed'].includes(payphoneStatus)">
          {{ t('PAYPHONE.REJECTED') }}
        </template>
        <template v-else-if="payphoneStatus === 'conflict'">
          {{ t('PAYPHONE.CONFLICT') }}
        </template>
        <ButtonV4
          v-if="['cancelled', 'failed'].includes(payphoneStatus)"
          :label="t('PAYPHONE.RETRY')"
          class="ms-3"
          variant="outline"
          sm
          @click="comparingPlans = true"
        />
      </div>
      <section
        v-if="payphonePlanId && payphoneEnabled"
        class="mb-4 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:p-6 dark:bg-n-solid-3"
        aria-live="polite"
      >
        <div class="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 class="m-0 text-heading-2">
              {{ t('PAYPHONE.CONFIRM_TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{ t('PAYPHONE.DURATION') }}
            </p>
          </div>
          <ButtonV4
            :label="t('PAYPHONE.CLOSE')"
            variant="outline"
            sm
          class="shrink-0"
            @click="
              payphonePlanId = null;
              payphoneQuote = null;
              payphonePayment = null;
            "
          />
        </div>
        <label class="mb-4 flex items-center gap-3 text-sm">
          <input
            v-model="payphoneNeedsInvoice"
            type="checkbox"
            class="size-4 accent-n-blue-9"
            :disabled="payphoneBusy || !!payphonePayment"
            @change="quotePayphone"
          />
          <span>{{ t('PAYPHONE.NEEDS_INVOICE') }}</span>
        </label>
        <div v-if="payphoneNeedsInvoice" class="mb-4 grid gap-3 sm:grid-cols-2">
          <input
            v-for="field in [
              'billing_tax_id_type',
              'billing_tax_id',
              'billing_name',
              'billing_email',
              'billing_phone',
              'billing_address',
            ]"
            :key="field"
            v-model="payphoneInvoice[field]"
            :placeholder="t(`PAYPHONE.INVOICE.${field}`)"
            :aria-label="t(`PAYPHONE.INVOICE.${field}`)"
            :disabled="payphoneBusy || !!payphonePayment"
            class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm dark:bg-n-solid-3"
          />
        </div>
        <dl
          v-if="payphoneQuote"
          class="grid grid-cols-2 gap-2 text-sm sm:max-w-md"
        >
          <dt class="text-n-slate-11">{{ t('PAYPHONE.SUBTOTAL') }}</dt>
          <dd class="m-0 text-end">
            {{ formatPayphoneAmount(payphoneQuote.base_cents, payphoneQuote.currency) }}
          </dd>
          <dt class="text-n-slate-11">{{ t('PAYPHONE.TAX') }}</dt>
          <dd class="m-0 text-end">
            {{ formatPayphoneAmount(payphoneQuote.tax_cents, payphoneQuote.currency) }}
          </dd>
          <dt class="text-n-slate-11">{{ t('PAYPHONE.COMMISSION') }}</dt>
          <dd class="m-0 text-end">
            {{ formatPayphoneAmount(payphoneQuote.commission_cents, payphoneQuote.currency) }}
          </dd>
          <dt class="font-medium">{{ t('PAYPHONE.TOTAL') }}</dt>
          <dd class="m-0 text-end font-semibold">
            {{ formatPayphoneAmount(payphoneQuote.amount, payphoneQuote.currency) }}
          </dd>
        </dl>
        <p
          v-if="payphoneError"
          role="alert"
          class="mt-3 text-sm text-n-ruby-11"
        >
          {{ payphoneError }}
        </p>
        <div v-if="!payphonePayment" class="mt-4">
          <ButtonV4
            :label="t('PAYPHONE.CONTINUE')"
            sm
            solid
            blue
            :is-loading="payphoneBusy || !payphoneQuote"
            :disabled="payphoneBusy || !payphoneQuote"
            @click="beginPayphonePayment"
          />
        </div>
        <div
          v-else-if="payphonePayment.box.preview"
          class="mt-4 space-y-3 rounded-lg border border-n-weak bg-n-slate-2 p-4"
        >
          <p class="m-0 text-sm">{{ t('PAYPHONE.PREVIEW_BOX') }}</p>
          <div class="flex flex-wrap gap-2">
            <ButtonV4
              :label="t('PAYPHONE.SIMULATE_APPROVED')"
              sm
              solid
              blue
              :disabled="payphoneBusy"
              @click="previewPayphone('approved')"
            />
            <ButtonV4
              :label="t('PAYPHONE.SIMULATE_REJECTED')"
              sm
              variant="outline"
              :disabled="payphoneBusy"
              @click="previewPayphone('cancelled')"
            />
            <ButtonV4
              :label="t('PAYPHONE.SIMULATE_PENDING')"
              sm
              variant="outline"
              :disabled="payphoneBusy"
              @click="previewPayphone('pending')"
            />
          </div>
        </div>
        <div v-else id="payphone-box" class="mt-4 min-h-12" />
        <p
          v-if="['pending', 'verifying'].includes(payphoneStatus)"
          role="status"
          class="mt-3 text-sm text-n-slate-11"
        >
          {{ t('PAYPHONE.VERIFYING') }}
        </p>
        <p
          v-else-if="payphoneStatus === 'approved'"
          role="status"
          class="mt-3 text-sm text-n-teal-11"
        >
          {{ t('PAYPHONE.APPROVED') }}
          {{ formattedPayphoneDate(payphonePayment?.period_end) }}
          <a
            v-if="payphoneHistory.length"
            href="#payphone-history"
            class="ms-2 text-n-blue-11 underline"
          >
            {{ t('PAYPHONE.HISTORY_LINK') }}
          </a>
        </p>
        <p
          v-else-if="['cancelled', 'failed'].includes(payphoneStatus)"
          role="status"
          class="mt-3 text-sm text-n-slate-11"
        >
          {{ t('PAYPHONE.REJECTED') }}
        </p>
      </section>
      <BillingCard
        v-if="!isOnChatwootCloud"
        class="mb-4"
        :title="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
        :description="$t('BILLING_SETTINGS.SELF_HOSTED.DESCRIPTION')"
      >
        <template #action>
          <ButtonV4
            :label="t('BILLING_SETTINGS.TABS.USO')"
            intent="secondary"
            sm
            @click="router.replace({ query: { ...route.query, tab: 'uso' } })"
          />
        </template>
        <div class="grid grid-cols-1 gap-4 divide-n-weak sm:grid-cols-3 sm:divide-x">
          <DetailItem :label="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')" :value="planName" />
          <DetailItem :label="$t('PAYPHONE.HISTORY_TABLE.STATUS')" :value="usagePlanStatus" />
          <DetailItem
            v-if="showPayphoneRenewalDate && payphonePeriodEnd"
            :label="$t('BILLING_SETTINGS.SELF_HOSTED.PAID_UNTIL')"
            :value="formattedPayphoneDate(payphonePeriodEnd)"
          />
        </div>
      </BillingCard>
      <section
        v-if="!isOnChatwootCloud || payphoneHistory.length"
        id="payphone-history"
        class="mb-4 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:p-6 dark:bg-n-solid-3"
      >
        <h2 class="mb-4 mt-0 text-heading-2">{{ t('PAYPHONE.HISTORY') }}</h2>
        <p v-if="isLoadingPayphone" class="m-0 text-sm text-n-slate-11" role="status">
          {{ t('ATTRIBUTES_MGMT.LOADING') }}
        </p>
        <p v-else-if="payphoneLoadFailed" class="m-0 text-sm text-n-ruby-11" role="alert">
          {{ t('PAYPHONE.HISTORY_ERROR') }}
        </p>
        <p v-else-if="!payphoneHistory.length" class="m-0 text-sm text-n-slate-11">
          {{ t('PAYPHONE.HISTORY_EMPTY') }}
        </p>
        <div v-else class="grid gap-3 md:hidden">
          <article
            v-for="payment in payphoneHistory"
            :key="payment.id"
            class="rounded-lg border border-n-weak p-3 text-sm"
          >
            <div class="flex justify-between gap-3">
              <strong>{{ payment.plan }}</strong>
              <span>{{ t(`PAYPHONE.STATES.${payment.status}`) }}</span>
            </div>
            <div class="mt-2 flex justify-between gap-3 text-n-slate-11">
              <span>{{ formattedPayphoneDate(payment.created_at) }}</span>
              <span>
                {{ formatPayphoneAmount(payment.amount, payment.currency) }}
              </span>
            </div>
            <p class="mb-0 mt-1 break-all text-xs text-n-slate-10">
              {{ payment.client_transaction_id }}
            </p>
          </article>
        </div>
        <div v-if="payphoneHistory.length" class="hidden overflow-x-auto md:block">
          <table class="w-full text-start text-sm">
            <thead class="text-n-slate-11">
              <tr>
                <th class="p-3 text-start">{{ t('PAYPHONE.HISTORY_TABLE.DATE') }}</th>
                <th class="p-3 text-start">{{ t('PAYPHONE.HISTORY_TABLE.PLAN') }}</th>
                <th class="p-3 text-start">{{ t('PAYPHONE.HISTORY_TABLE.STATUS') }}</th>
                <th class="p-3 text-end">{{ t('PAYPHONE.HISTORY_TABLE.AMOUNT') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="payment in payphoneHistory" :key="payment.id" class="border-t border-n-weak">
                <td class="p-3">{{ formattedPayphoneDate(payment.created_at) }}</td>
                <td class="p-3">{{ payment.plan }}</td>
                <td class="p-3">{{ t(`PAYPHONE.STATES.${payment.status}`) }}</td>
                <td class="p-3 text-end">{{ formatPayphoneAmount(payment.amount, payment.currency) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
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
      <section v-else-if="isOnChatwootCloud" class="grid gap-4">
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
            class="grid grid-cols-1 gap-4 divide-n-weak sm:grid-cols-3 sm:divide-x lg:grid-cols-4"
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
              v-else-if="showPayphoneRenewalDate && subscriptionRenewsOn"
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
                v-if="isOnChatwootCloud && canPurchaseCredits"
                sm
                solid
                blue
                @click="openPurchaseCreditsModal"
              >
                {{ $t('BILLING_SETTINGS.TOPUP.BUY_CREDITS') }}
              </ButtonV4>
            </div>
          </template>
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
      </section>
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
      <PurchaseCreditsModal
        v-if="isOnChatwootCloud"
        ref="purchaseCreditsModalRef"
        @success="handleTopupSuccess"
      />
      </div>
    </template>
  </SettingsLayout>
</template>
