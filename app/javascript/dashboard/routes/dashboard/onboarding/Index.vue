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
import OnboardingShell from './shared/OnboardingShell.vue';
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

const CURRENT_STEP = 1;
const changingLocation = ref(false);
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
const locationSummary = computed(() =>
  [
    countryOptions.value.find(option => option.value === country.value)?.label,
    languageOptions.value.find(option => option.value === locale.value)?.label,
    timezone.value &&
      `${timezone.value.split('/').pop().replace(/_/g, ' ')} (${new Intl.DateTimeFormat(interfaceLocale.value, { timeZone: timezone.value, timeZoneName: 'shortOffset' }).formatToParts(new Date()).find(part => part.type === 'timeZoneName').value})`,
  ]
    .filter(Boolean)
    .join(' · ')
);
const hasLocation = computed(
  () => country.value && locale.value && timezone.value
);
const previewBusiness = computed(
  () => name.value.trim() || t('ONBOARDING_LAYOUT.YOUR_BUSINESS')
);
const previewReplies = computed(() => ({
  appointments: t('ONBOARDING_LAYOUT.PREVIEW_REPLIES.appointments'),
  commerce: t('ONBOARDING_LAYOUT.PREVIEW_REPLIES.commerce'),
  services: t('ONBOARDING_LAYOUT.PREVIEW_REPLIES.services'),
  other: t('ONBOARDING_LAYOUT.PREVIEW_REPLIES.other'),
}));
const reviewing = computed(() =>
  ['inbox_setup', 'assistant'].includes(
    currentAccount.value?.custom_attributes?.onboarding_step
  )
);
const submitLabel = computed(() => {
  if (isEnriching.value) return t('ONBOARDING_NEXT.SETTING_UP');
  if (isSubmitting.value) return t('ONBOARDING_NEXT.SAVING');
  return t('ONBOARDING_NEXT.CONTINUE');
});

onMounted(() => useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_VISITED));

const handleSubmit = async () => {
  if (isEnriching.value || isSubmitting.value) return;
  if (reviewing.value) {
    router.push({
      name: 'onboarding_inbox_setup',
      params: { accountId: accountId.value },
    });
    return;
  }
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
  <OnboardingShell
    :current="CURRENT_STEP"
    :title="t('ONBOARDING_NEXT.TITLE')"
    :subtitle="t('ONBOARDING_NEXT.SUBTITLE')"
  >
    <template #eyebrow>
      <span class="i-lucide-sparkles size-5" aria-hidden="true" />{{
        t('ONBOARDING_LAYOUT.MADE_FOR_YOU')
      }}
    </template>
    <template #intro>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ t('ONBOARDING_LAYOUT.DURATION') }}
      </p>
    </template>
    <div
      class="grid items-start gap-5 lg:grid-cols-[minmax(0,2.25fr)_minmax(0,1fr)]"
    >
      <div
        class="rounded-xl border border-n-weak bg-n-solid-1 p-5 shadow-sm dark:bg-n-solid-3 [@media(max-height:50rem)]:p-4"
      >
        <p class="mb-4 flex items-center gap-2 text-sm text-n-teal-11">
          <span
            class="i-lucide-circle-check size-4 shrink-0"
            aria-hidden="true"
          />{{ t('ONBOARDING_NEXT.EMAIL_VERIFIED') }}
        </p>
        <p v-if="reviewing" class="text-sm text-n-slate-11">
          {{ t('ONBOARDING_LAYOUT.SAVED_DETAILS') }}
        </p>
        <form
          id="business-details-form"
          class="space-y-3"
          novalidate
          @submit.prevent="handleSubmit"
        >
          <AuthField
            id="business-name"
            v-model="name"
            :disabled="reviewing"
            name="name"
            autocomplete="organization"
            required
            :label="t('ONBOARDING_NEXT.FIELDS.NAME')"
            :error="v$.name.$error ? t('ONBOARDING_NEXT.NAME_REQUIRED') : ''"
            @blur="v$.name.$touch"
          />
          <fieldset
            :disabled="reviewing"
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
                compact
                required
                :disabled="reviewing"
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
          <div class="border-t border-n-weak pt-3">
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <p class="m-0 text-sm font-medium">
                  {{ t('ONBOARDING_LAYOUT.LOCATION') }}
                </p>
                <p
                  v-if="hasLocation"
                  class="m-0 mt-1 text-sm leading-6 text-n-slate-11"
                >
                  {{ locationSummary }}
                </p>
              </div>
              <button
                v-if="hasLocation && !reviewing"
                type="button"
                class="min-h-11 shrink-0 rounded-lg px-2 text-sm font-medium text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :aria-expanded="changingLocation"
                aria-controls="location-fields"
                @click="changingLocation = !changingLocation"
              >
                {{ t('ONBOARDING_LAYOUT.CHANGE') }}
              </button>
            </div>
            <div
              v-show="!reviewing && (changingLocation || !hasLocation)"
              id="location-fields"
              class="mt-3 space-y-3"
            >
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <OnboardingFormSelect
                  v-model="country"
                  :label="t('ONBOARDING_NEXT.FIELDS.COUNTRY')"
                  :options="countryOptions"
                  :placeholder="
                    t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_COUNTRY')
                  "
                  show-search
                  allow-deselect
                />
                <OnboardingFormSelect
                  v-model="locale"
                  :label="t('ONBOARDING_NEXT.FIELDS.LANGUAGE')"
                  :options="languageOptions"
                  :placeholder="
                    t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_LANGUAGE')
                  "
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
            </div>
          </div>
        </form>
      </div>
      <aside
        class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-sm dark:bg-n-solid-3"
        :aria-label="t('ONBOARDING_LAYOUT.PREVIEW')"
      >
        <div class="border-b border-n-weak p-5">
          <p
            class="m-0 text-xs font-medium uppercase tracking-widest text-n-blue-11"
          >
            {{ t('ONBOARDING_LAYOUT.PREVIEW') }}
          </p>
          <h2 class="mb-0 mt-2 text-base font-medium">
            {{ t('ONBOARDING_LAYOUT.PREVIEW_TITLE') }}
          </h2>
        </div>
        <div class="space-y-4 p-5">
          <div class="flex items-center gap-3">
            <span
              class="i-woot-captain size-8 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
            <div class="min-w-0">
              <p class="m-0 break-words font-medium">{{ previewBusiness }}</p>
              <p class="m-0 mt-1 text-xs text-n-slate-11">
                {{
                  t('ONBOARDING_LAYOUT.ASSISTANT_ROLE', {
                    type:
                      businessTypeOptions.find(
                        option => option.value === businessType
                      )?.label || '',
                  })
                }}
              </p>
            </div>
          </div>
          <p
            class="m-0 rounded-xl bg-n-slate-3 p-4 text-sm leading-6"
            data-testid="business-preview"
          >
            {{
              t('ONBOARDING_LAYOUT.PREVIEW_GREETING', {
                business: previewBusiness,
              })
            }}
            {{ previewReplies[businessType || 'other'] }}
          </p>
          <p class="m-0 text-xs leading-5 text-n-slate-11">
            {{ t('ONBOARDING_LAYOUT.PREVIEW_HINT') }}
          </p>
        </div>
      </aside>
    </div>
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
  </OnboardingShell>
</template>
