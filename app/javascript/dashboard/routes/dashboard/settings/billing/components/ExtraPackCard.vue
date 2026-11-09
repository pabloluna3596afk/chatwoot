<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ButtonV4 from 'next/button/Button.vue';
import InfoChip from 'next/ListCard/InfoChip.vue';

const props = defineProps({
  pack: { type: Object, required: true },
  bestValue: { type: Boolean, default: false },
});
const emit = defineEmits(['request']);
const { t, locale } = useI18n();
const units = computed(() =>
  new Intl.NumberFormat(locale.value).format(props.pack.units)
);
const unitsKey = computed(() => {
  if (props.pack.bucket === 'internal') {
    return 'BILLING_SETTINGS.EXTRAS.UNITS_ACTIONS';
  }
  return 'BILLING_SETTINGS.EXTRAS.UNITS_RESPONSES';
});
const price = computed(
  () =>
    `USD ${new Intl.NumberFormat(locale.value).format(props.pack.price_usd)}`
);
const unitPrice = computed(() =>
  new Intl.NumberFormat(locale.value, {
    minimumFractionDigits: 3,
    maximumFractionDigits: 3,
  }).format(props.pack.price_usd / props.pack.units)
);
</script>

<template>
  <article
    class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak p-5"
  >
    <div class="min-h-6">
      <InfoChip v-if="bestValue">
        {{ t('BILLING_SETTINGS.EXTRAS.BEST_VALUE') }}
      </InfoChip>
    </div>
    <h4 class="m-0 text-heading-2">
      {{ t(unitsKey, { count: units }) }}
    </h4>
    <p class="m-0 text-heading-3">{{ price }}</p>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('BILLING_SETTINGS.EXTRAS.UNIT_PRICE', { price: unitPrice }) }}
    </p>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('BILLING_SETTINGS.EXTRAS.VALIDITY', { days: pack.validity_days }) }}
    </p>
    <ButtonV4
      class="mt-auto"
      intent="primary"
      :label="t('BILLING_SETTINGS.EXTRAS.REQUEST')"
      @click="emit('request')"
    />
  </article>
</template>
