<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ButtonV4 from 'next/button/Button.vue';
import BagIcon from 'next/plans/BagIcon.vue';
import BillingCard from './components/BillingCard.vue';
import ExtraPackCard from './components/ExtraPackCard.vue';
import { formatBillingDate } from './billingDate';

const props = defineProps({
  catalog: { type: Object, default: null },
  captainLimits: { type: Object, default: () => ({}) },
  planSlug: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
});
const emit = defineEmits(['request']);
const { t, locale } = useI18n();
const groups = computed(() =>
  [
    {
      key: 'captain_responses',
      limitKey: 'responses',
      title: t('BILLING_SETTINGS.EXTRAS.BAGS.RESPONSES'),
    },
    {
      key: 'copilot',
      limitKey: 'copilot',
      title: t('BILLING_SETTINGS.EXTRAS.BAGS.COPILOT'),
    },
    {
      key: 'internal',
      limitKey: 'internal',
      title: t('BILLING_SETTINGS.EXTRAS.BAGS.INTERNAL'),
    },
  ].map(group => {
    const packs =
      props.catalog?.packs.filter(pack => pack.bucket === group.key) || [];
    const best = packs.reduce(
      (cheapest, pack) =>
        !cheapest ||
        pack.price_usd / pack.units < cheapest.price_usd / cheapest.units
          ? pack
          : cheapest,
      null
    );
    const balance = props.captainLimits?.[group.limitKey];
    return {
      ...group,
      packs,
      bestId: best?.id,
      available: balance?.extra_available || 0,
      expiry: balance?.extra_next_expiry,
    };
  })
);
const hasBalance = computed(() =>
  groups.value.some(group => group.available > 0)
);
const monthly = computed(() => {
  const prices = props.catalog?.monthly[props.planSlug] || {};
  return [
    { key: 'agent', title: t('BILLING_SETTINGS.EXTRAS.MONTHLY.AGENT') },
    { key: 'bot', title: t('BILLING_SETTINGS.EXTRAS.MONTHLY.BOT') },
    { key: 'inbox', title: t('BILLING_SETTINGS.EXTRAS.MONTHLY.INBOX') },
    {
      key: 'storage_100mb',
      title: t('BILLING_SETTINGS.EXTRAS.MONTHLY.STORAGE_100MB'),
    },
    {
      key: 'storage_250mb',
      title: t('BILLING_SETTINGS.EXTRAS.MONTHLY.STORAGE_250MB'),
    },
  ]
    .filter(item => prices[item.key] > 0)
    .map(item => ({ ...item, price: prices[item.key] }));
});
const formatNumber = value => new Intl.NumberFormat(locale.value).format(value);
</script>

<template>
  <section
    id="billing-panel-extras"
    role="tabpanel"
    aria-labelledby="billing-tab-extras"
    class="min-w-0 space-y-4"
  >
    <p v-if="isLoading" role="status" class="text-sm text-n-slate-11">
      {{ t('BILLING_SETTINGS.EXTRAS.LOADING') }}
    </p>
    <p v-else-if="!catalog" role="alert" class="text-sm text-n-ruby-11">
      {{ t('BILLING_SETTINGS.EXTRAS.ERROR') }}
    </p>
    <template v-else>
      <BillingCard
        :title="t('BILLING_SETTINGS.EXTRAS.BALANCES')"
        description=""
      >
        <div v-if="hasBalance" class="divide-y divide-n-weak px-5">
          <div
            v-for="group in groups"
            :key="group.key"
            class="flex flex-wrap items-center justify-between gap-3 py-3"
          >
            <span class="flex items-center gap-2 text-sm font-medium">
              <BagIcon :bag="group.key" class="size-4 shrink-0" />{{
                group.title
              }}
            </span>
            <div class="text-sm text-n-slate-11">
              <template v-if="group.available > 0">
                <p class="m-0 text-n-slate-12">
                  {{
                    t('BILLING_SETTINGS.EXTRAS.AVAILABLE', {
                      count: formatNumber(group.available),
                    })
                  }}
                </p>
                <p v-if="group.expiry" class="m-0">
                  {{
                    t('BILLING_SETTINGS.EXTRAS.NEXT_EXPIRY', {
                      date: formatBillingDate(group.expiry, locale),
                    })
                  }}
                </p>
              </template>
              <span v-else>{{ t('BILLING_SETTINGS.EXTRAS.NO_BALANCE') }}</span>
            </div>
          </div>
        </div>
        <p v-else class="m-0 px-5 text-sm text-n-slate-11">
          {{ t('BILLING_SETTINGS.EXTRAS.EMPTY') }}
          <a href="#extras-packs" class="text-n-blue-11 underline">{{
            t('BILLING_SETTINGS.EXTRAS.PACKS')
          }}</a>
        </p>
      </BillingCard>
      <BillingCard
        id="extras-packs"
        :title="t('BILLING_SETTINGS.EXTRAS.PACKS')"
        description=""
      >
        <div v-for="group in groups" :key="group.key" class="space-y-3 px-5">
          <h3 class="m-0 flex items-center gap-2 text-heading-3">
            <BagIcon :bag="group.key" class="size-4 shrink-0" />{{
              group.title
            }}
          </h3>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.EXTRAS.RULES') }}
          </p>
          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <ExtraPackCard
              v-for="pack in group.packs"
              :key="pack.id"
              :pack="pack"
              :best-value="pack.id === group.bestId"
              @request="emit('request')"
            />
          </div>
          <p v-if="!group.packs.length" class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.EXTRAS.NO_PACKS') }}
          </p>
        </div>
      </BillingCard>
      <BillingCard
        :title="t('BILLING_SETTINGS.EXTRAS.MONTHLY_TITLE')"
        :description="t('BILLING_SETTINGS.EXTRAS.MONTHLY_NOTE')"
      >
        <div class="divide-y divide-n-weak px-5">
          <div
            v-for="item in monthly"
            :key="item.key"
            class="flex flex-wrap items-center justify-between gap-3 py-3"
          >
            <span class="text-sm font-medium">{{ item.title }}</span>
            <div class="flex flex-wrap items-center gap-3">
              <span class="text-sm text-n-slate-11">{{
                t('BILLING_SETTINGS.EXTRAS.MONTHLY_PRICE', {
                  price: formatNumber(item.price),
                })
              }}</span>
              <ButtonV4
                intent="primary"
                sm
                :label="t('BILLING_SETTINGS.EXTRAS.REQUEST')"
                @click="emit('request')"
              />
            </div>
          </div>
          <p v-if="!monthly.length" class="m-0 text-sm text-n-slate-11">
            {{ t('BILLING_SETTINGS.EXTRAS.NO_MONTHLY') }}
          </p>
        </div>
      </BillingCard>
    </template>
  </section>
</template>
