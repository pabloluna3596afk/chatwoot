<script setup>
import { ref, computed, onMounted } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import countries from 'shared/constants/countries';
import AuthSplitLayout from 'v3/components/Auth/AuthSplitLayout.vue';
import AuthStepHeader from 'v3/components/Auth/AuthStepHeader.vue';
import AuthField from 'v3/components/Auth/AuthField.vue';
import AuthButton from 'v3/components/Auth/AuthButton.vue';
import AuthChoiceCard from 'v3/components/Auth/AuthChoiceCard.vue';
import AuthFeedback from 'v3/components/Auth/AuthFeedback.vue';
import OnboardingFormSelect from './account-details/OnboardingFormSelect.vue';
import { useAccountEnrichment } from './account-details/useAccountEnrichment';
import { businessTimezoneOptions } from './account-details/timezoneOptions';

const { t, locale: interfaceLocale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount, finishOnboarding } = useAccount();

const CURRENT_STEP = 2;
// The shared phone-country list still contains the retired Netherlands Antilles code.
const RETIRED_COUNTRY_CODE = 'AN';
const STEP_ROUTES = { inbox_setup: 'onboarding_inbox_setup' };
const name = ref('');
const businessType = ref('');
const country = ref('');
const website = ref('');
const locale = ref('');
const timezone = ref('');
const isSubmitting = ref(false);
const submitError = ref('');
const { isEnriching, getChangedFields } = useAccountEnrichment({
  name,
  businessType,
  country,
  locale,
  website,
  timezone,
});

const v$ = useVuelidate(
  { name: { required }, businessType: { required } },
  { name, businessType }
);
const businessTypeOptions = computed(() => [
  {
    value: 'appointments',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.appointments'),
    description: t('ONBOARDING_NEXT.BUSINESS_DESCRIPTIONS.appointments'),
    icon: 'i-lucide-calendar',
  },
  {
    value: 'commerce',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.commerce'),
    description: t('ONBOARDING_NEXT.BUSINESS_DESCRIPTIONS.commerce'),
    icon: 'i-lucide-store',
  },
  {
    value: 'services',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.services'),
    description: t('ONBOARDING_NEXT.BUSINESS_DESCRIPTIONS.services'),
    icon: 'i-lucide-briefcase',
  },
  {
    value: 'other',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.other'),
    description: t('ONBOARDING_NEXT.BUSINESS_DESCRIPTIONS.other'),
    icon: 'i-lucide-sparkles',
  },
]);
const languageOptions = computed(() => [
  { value: 'es', label: t('ONBOARDING_NEXT.LANGUAGES.ES') },
  { value: 'en', label: t('ONBOARDING_NEXT.LANGUAGES.EN') },
]);
const countryOptions = computed(() => {
  const languageTag = interfaceLocale.value.replace('_', '-');
  const names = new Intl.DisplayNames([languageTag], {
    type: 'region',
  });
  return countries
    .filter(({ id }) => id !== RETIRED_COUNTRY_CODE)
    .map(({ id }) => ({ value: id, label: names.of(id) }))
    .sort((a, b) => a.label.localeCompare(b.label, languageTag));
});
const timezoneOptions = computed(() =>
  businessTimezoneOptions(timezone.value, interfaceLocale.value)
);
const submitLabel = computed(() => {
  if (isEnriching.value) return t('ONBOARDING_NEXT.SETTING_UP');
  if (isSubmitting.value) return t('ONBOARDING_NEXT.SAVING');
  return t('ONBOARDING_NEXT.CONTINUE');
});

onMounted(() => useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_VISITED));

const handleSubmit = async () => {
  if (isEnriching.value || isSubmitting.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) {
    document
      .querySelector(
        v$.value.name.$error ? '#business-name' : '[name=business_type]'
      )
      ?.focus();
    return;
  }

  const fieldsChanged = getChangedFields();
  const trimmedWebsite = website.value.trim();
  const websiteUrl =
    trimmedWebsite && !/^https?:\/\//i.test(trimmedWebsite)
      ? `https://${trimmedWebsite}`
      : trimmedWebsite;

  isSubmitting.value = true;
  submitError.value = '';
  try {
    await finishOnboarding({
      name: name.value.trim(),
      business_type: businessType.value,
      country: country.value,
      locale: locale.value,
      timezone: timezone.value,
      website: websiteUrl,
      onboarding_step: 'account_details',
    });
    useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_COMPLETED, {
      has_enriched_data: Boolean(
        currentAccount.value?.custom_attributes?.brand_info
      ),
      fields_changed: fieldsChanged,
      business_type: businessType.value,
    });
    useAlert(t('ONBOARDING_NEXT.SUCCESS'));

    const nextStep = currentAccount.value?.custom_attributes?.onboarding_step;
    await store.dispatch('setUser');
    if (STEP_ROUTES[nextStep]) {
      router.push({
        name: STEP_ROUTES[nextStep],
        params: { accountId: accountId.value },
      });
    } else {
      router.push({ name: 'home', params: { accountId: accountId.value } });
    }
  } catch {
    submitError.value = t('ONBOARDING_NEXT.ERROR');
    useAlert(t('ONBOARDING_NEXT.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <AuthSplitLayout
    :title="t('ONBOARDING_NEXT.MARKETING.TITLE')"
    :subtitle="t('ONBOARDING_NEXT.MARKETING.SUBTITLE')"
    onboarding
    scrollable
  >
    <AuthStepHeader
      :title="t('ONBOARDING_NEXT.TITLE')"
      :subtitle="t('ONBOARDING_NEXT.SUBTITLE')"
      :step-name="t('ONBOARDING_NEXT.TITLE')"
      :current="CURRENT_STEP"
    />
    <form
      id="business-details-form"
      class="space-y-4"
      novalidate
      @submit.prevent="handleSubmit"
    >
      <AuthField
        id="business-name"
        v-model="name"
        name="name"
        autocomplete="organization"
        required
        :label="t('ONBOARDING_NEXT.FIELDS.NAME')"
        :error="v$.name.$error ? t('ONBOARDING_NEXT.NAME_REQUIRED') : ''"
        @blur="v$.name.$touch"
      />
      <fieldset
        role="radiogroup"
        aria-labelledby="business-type-label"
        :aria-invalid="v$.businessType.$error"
        :aria-describedby="
          v$.businessType.$error ? 'business-type-error' : undefined
        "
      >
        <legend
          id="business-type-label"
          class="mb-2 text-sm font-medium leading-5 text-n-slate-12"
        >
          {{ t('ONBOARDING_NEXT.FIELDS.BUSINESS_TYPE') }}
        </legend>
        <div class="grid grid-cols-2 gap-2">
          <AuthChoiceCard
            v-for="(option, index) in businessTypeOptions"
            :key="option.value"
            v-model="businessType"
            name="business_type"
            required
            v-bind="option"
            :first="index === 0"
            :invalid="v$.businessType.$error"
          />
        </div>
        <AuthFeedback
          v-if="v$.businessType.$error"
          id="business-type-error"
          class="mt-2"
          error
        >
          {{ t('ONBOARDING_NEXT.BUSINESS_TYPE_REQUIRED') }}
        </AuthFeedback>
      </fieldset>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <OnboardingFormSelect
          v-model="country"
          :label="t('ONBOARDING_NEXT.FIELDS.COUNTRY')"
          :options="countryOptions"
          :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_COUNTRY')"
          show-search
          allow-deselect
        />
        <OnboardingFormSelect
          v-model="locale"
          :label="t('ONBOARDING_NEXT.FIELDS.LANGUAGE')"
          :options="languageOptions"
          :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_LANGUAGE')"
        />
      </div>
      <OnboardingFormSelect
        v-model="timezone"
        :label="t('ONBOARDING_NEXT.FIELDS.TIMEZONE')"
        :options="timezoneOptions"
        :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_TIMEZONE')"
        show-search
      />
      <AuthField
        id="business-website"
        v-model="website"
        name="website"
        inputmode="url"
        autocomplete="url"
        :label="t('ONBOARDING_NEXT.FIELDS.WEBSITE')"
        :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.ENTER_WEBSITE')"
      />
    </form>
    <template #footer>
      <AuthFeedback v-if="submitError" error>{{ submitError }}</AuthFeedback>
      <AuthButton
        type="submit"
        form="business-details-form"
        :loading="isSubmitting || isEnriching"
        :disabled="isSubmitting || isEnriching"
      >
        {{ submitLabel }}
      </AuthButton>
    </template>
  </AuthSplitLayout>
</template>
