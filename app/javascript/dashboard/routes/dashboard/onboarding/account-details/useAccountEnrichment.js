import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import ct from 'countries-and-timezones';
import { useAccount } from 'dashboard/composables/useAccount';

const ENRICHMENT_TIMEOUT = 30000;

// Keep the enrichment wait and prefills shared with the business form. Late
// account updates can refresh suggestions only while the field is untouched.
export function useAccountEnrichment(fields) {
  const { currentAccount } = useAccount();

  const enrichmentTimedOut = ref(false);
  const isEnriching = computed(
    () =>
      !enrichmentTimedOut.value &&
      currentAccount.value?.custom_attributes?.onboarding_step === 'enrichment'
  );

  const initialValues = {};

  const populateFormFields = () => {
    const account = currentAccount.value || {};
    const attrs = account.custom_attributes || {};
    const browserTimezone =
      Intl.DateTimeFormat().resolvedOptions().timeZone || '';
    const browserLocale = new Intl.Locale(navigator.language);
    const timezoneCountries = ct.getTimezone(browserTimezone)?.countries || [];
    const localeCountry =
      browserTimezone !== 'UTC' &&
      browserLocale.region &&
      ct.getCountry(browserLocale.region)
        ? browserLocale.region
        : '';
    const detectedCountry =
      timezoneCountries.length === 1 ? timezoneCountries[0] : localeCountry;
    const detectedLocale = ['es', 'en'].includes(browserLocale.language)
      ? browserLocale.language
      : '';
    const defaults = {
      name: account.name || '',
      businessType: attrs.business_type || '',
      country: attrs.country || detectedCountry,
      locale: ['es', 'en'].includes(account.locale)
        ? account.locale
        : detectedLocale,
      website: attrs.website || attrs.brand_info?.domain || '',
      timezone: attrs.timezone || browserTimezone,
    };

    Object.entries(defaults).forEach(([key, value]) => {
      const field = fields[key];
      const untouched =
        key in initialValues
          ? field.value === initialValues[key]
          : !field.value;
      if (!untouched) return;
      field.value = value;
      initialValues[key] = value;
    });
  };

  let enrichmentTimer = null;
  const startEnrichmentTimer = () => {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
    enrichmentTimer = setTimeout(() => {
      enrichmentTimedOut.value = true;
      populateFormFields();
    }, ENRICHMENT_TIMEOUT);
  };

  onMounted(() => {
    populateFormFields();
    if (isEnriching.value) startEnrichmentTimer();
  });

  onUnmounted(() => {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
  });

  watch(isEnriching, enriching => {
    if (enriching) {
      startEnrichmentTimer();
    } else {
      if (enrichmentTimer) clearTimeout(enrichmentTimer);
      populateFormFields();
    }
  });

  watch(currentAccount, populateFormFields, { deep: true });

  const getChangedFields = () =>
    Object.entries(fields)
      .filter(([key, field]) => field.value !== initialValues[key])
      .map(([key]) => (key === 'businessType' ? 'business_type' : key));

  return { isEnriching, getChangedFields };
}
