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
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import OnboardingFormSelect from './account-details/OnboardingFormSelect.vue';
import { useAccountEnrichment } from './account-details/useAccountEnrichment';
import { businessTimezoneOptions } from './account-details/timezoneOptions';

const { t, locale: interfaceLocale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount, finishOnboarding } = useAccount();

const CURRENT_STEP = 2;
const TOTAL_STEPS = 5;
// The shared phone-country list still contains the retired Netherlands Antilles code.
const RETIRED_COUNTRY_CODE = 'AN';
const STEP_ROUTES = { inbox_setup: 'onboarding_inbox_setup' };
const RADIO_ARROW_STEPS = {
  ArrowRight: 1,
  ArrowDown: 1,
  ArrowLeft: -1,
  ArrowUp: -1,
};
const INPUT_CLASS =
  'reset-base m-0 h-14 w-full rounded-full border-0 bg-n-solid-1 px-5 text-base text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand dark:bg-n-solid-3';

const name = ref('');
const businessType = ref('');
const country = ref('');
const website = ref('');
const locale = ref('');
const timezone = ref('');
const isSubmitting = ref(false);
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
    icon: 'i-lucide-calendar',
  },
  {
    value: 'commerce',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.commerce'),
    icon: 'i-lucide-store',
  },
  {
    value: 'services',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.services'),
    icon: 'i-lucide-briefcase',
  },
  {
    value: 'other',
    label: t('ONBOARDING_NEXT.BUSINESS_TYPES.other'),
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

const handleBusinessTypeKeydown = (event, index) => {
  const step = RADIO_ARROW_STEPS[event.key];
  if (!step) return;
  event.preventDefault();
  const options = businessTypeOptions.value;
  const next = (index + step + options.length) % options.length;
  businessType.value = options[next].value;
  const radios = event.currentTarget
    .closest('[role="radiogroup"]')
    .querySelectorAll('input');
  radios[next].focus();
};

const handleSubmit = async () => {
  if (isEnriching.value || isSubmitting.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) return;

  const fieldsChanged = getChangedFields();
  const trimmedWebsite = website.value.trim();
  const websiteUrl =
    trimmedWebsite && !/^https?:\/\//i.test(trimmedWebsite)
      ? `https://${trimmedWebsite}`
      : trimmedWebsite;

  isSubmitting.value = true;
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
    if (STEP_ROUTES[nextStep]) {
      router.push({
        name: STEP_ROUTES[nextStep],
        params: { accountId: accountId.value },
      });
    } else {
      await store.dispatch('setUser');
      router.push({ name: 'home', params: { accountId: accountId.value } });
    }
  } catch {
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
    scrollable
  >
    <header class="mb-4">
      <p class="mb-2 text-sm font-medium text-n-slate-11">
        {{
          t('ONBOARDING_NEXT.STEP', {
            current: CURRENT_STEP,
            total: TOTAL_STEPS,
          })
        }}
      </p>
      <div
        role="progressbar"
        :aria-label="t('ONBOARDING_NEXT.PROGRESS')"
        :aria-valuenow="CURRENT_STEP"
        :aria-valuemin="0"
        :aria-valuemax="TOTAL_STEPS"
        class="mb-3 flex gap-1.5"
      >
        <span
          v-for="step in TOTAL_STEPS"
          :key="step"
          class="h-1 flex-1 rounded-full"
          :class="step <= CURRENT_STEP ? 'bg-n-slate-12' : 'bg-n-slate-4'"
        />
      </div>
      <h2 class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl">
        {{ t('ONBOARDING_NEXT.TITLE') }}
      </h2>
      <p class="mt-2 mb-0 text-sm text-n-slate-11">
        {{ t('ONBOARDING_NEXT.SUBTITLE') }}
      </p>
    </header>

    <form
      id="business-details-form"
      class="space-y-3"
      novalidate
      @submit.prevent="handleSubmit"
    >
      <div class="space-y-2">
        <label for="business-name" class="text-sm font-medium text-n-slate-12">
          {{ t('ONBOARDING_NEXT.FIELDS.NAME') }}
        </label>
        <input
          id="business-name"
          v-model="name"
          name="name"
          autocomplete="organization"
          required
          :class="[INPUT_CLASS, { '!outline-n-ruby-8': v$.name.$error }]"
          :aria-invalid="v$.name.$error"
          :aria-describedby="v$.name.$error ? 'business-name-error' : undefined"
          @blur="v$.name.$touch"
        />
        <p
          v-if="v$.name.$error"
          id="business-name-error"
          class="mb-0 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ t('ONBOARDING_NEXT.NAME_REQUIRED') }}
        </p>
      </div>

      <fieldset
        class="space-y-2"
        role="radiogroup"
        aria-labelledby="business-type-label"
        :aria-describedby="
          v$.businessType.$error ? 'business-type-error' : undefined
        "
      >
        <legend
          id="business-type-label"
          class="mb-2 text-sm font-medium text-n-slate-12"
        >
          {{ t('ONBOARDING_NEXT.FIELDS.BUSINESS_TYPE') }}
        </legend>
        <div class="grid grid-cols-2 gap-2">
          <label
            v-for="(option, index) in businessTypeOptions"
            :key="option.value"
            class="relative cursor-pointer"
          >
            <input
              v-model="businessType"
              type="radio"
              role="radio"
              name="business_type"
              :value="option.value"
              :tabindex="
                businessType === option.value || (!businessType && index === 0)
                  ? 0
                  : -1
              "
              required
              :aria-invalid="v$.businessType.$error"
              class="peer sr-only"
              @keydown="handleBusinessTypeKeydown($event, index)"
            />
            <span
              class="flex min-h-16 h-full items-center justify-center gap-2 rounded-2xl border border-n-weak px-3 py-3 text-center text-sm font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-1 peer-checked:border-n-brand peer-checked:bg-n-brand/10 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-n-brand"
            >
              <span
                :class="option.icon"
                class="size-4 shrink-0"
                aria-hidden="true"
              />
              {{ option.label }}
            </span>
            <span
              class="i-lucide-check absolute end-2 top-2 hidden size-3 text-n-brand peer-checked:block"
              aria-hidden="true"
            />
          </label>
        </div>
        <p
          v-if="v$.businessType.$error"
          id="business-type-error"
          class="mb-0 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ t('ONBOARDING_NEXT.BUSINESS_TYPE_REQUIRED') }}
        </p>
      </fieldset>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
      <div class="space-y-2">
        <label
          for="business-website"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('ONBOARDING_NEXT.FIELDS.WEBSITE') }}
        </label>
        <input
          id="business-website"
          v-model="website"
          name="website"
          type="text"
          inputmode="url"
          autocomplete="url"
          :class="INPUT_CLASS"
          :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.ENTER_WEBSITE')"
        />
      </div>
    </form>
    <template #footer>
      <button
        type="submit"
        form="business-details-form"
        class="flex h-14 w-full items-center justify-center gap-2 rounded-full bg-n-slate-12 px-6 text-base font-medium text-n-solid-1 transition-opacity hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
        :aria-busy="isSubmitting || isEnriching"
        :disabled="isSubmitting || isEnriching"
      >
        <Spinner
          v-if="isSubmitting || isEnriching"
          :size="20"
          aria-hidden="true"
        />
        {{ submitLabel }}
      </button>
    </template>
  </AuthSplitLayout>
</template>
