<script setup>
import { computed, defineAsyncComponent, ref, watch } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useI18n, Translation as I18nT } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert, useTrack } from 'dashboard/composables';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import AuthSplitLayout from 'v3/components/Auth/AuthSplitLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AuthStepHeader from 'v3/components/Auth/AuthStepHeader.vue';
import AuthButton from 'v3/components/Auth/AuthButton.vue';
import AuthFeedback from 'v3/components/Auth/AuthFeedback.vue';
import { AUTH_LINK_CLASS } from 'v3/components/Auth/authStyles';
import { useChannelConfig } from './inbox-setup/useChannelConfig';
import InboxChannelsDialog from './inbox-setup/InboxChannelsDialog.vue';
import LegacyInboxSetup from './LegacyInboxSetup.vue';

const WhatsappGuideDialog = defineAsyncComponent(
  () => import('./inbox-setup/WhatsappGuideDialog.vue')
);
const MOBILE_BREAKPOINT = 768;
const MOBILE_USER_AGENT = /Android|iPhone|iPad|iPod|Mobile/i;
const CURRENT_STEP = 3;
const { t } = useI18n();
const connectionSteps = computed(() => [
  {
    icon: 'i-lucide-log-in',
    label: t('ONBOARDING_WHATSAPP.STEPS.META'),
  },
  {
    icon: 'i-lucide-smartphone',
    label: t('ONBOARDING_WHATSAPP.STEPS.NUMBER'),
  },
  {
    icon: 'i-lucide-messages-square',
    label: t('ONBOARDING_WHATSAPP.STEPS.READY'),
  },
]);
const router = useRouter();
const store = useStore();
const { accountId, currentAccount, finishOnboarding } = useAccount();
const { isConfigured } = useChannelConfig();
const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
const inboxes = useMapGetter('inboxes/getInboxes');
const isNewOnboarding = computed(
  () => currentAccount.value?.custom_attributes?.onboarding_version === 2
);
const isAvailable = computed(() => isConfigured('whatsapp'));
const state = ref('idle');
const createdInbox = ref(null);
const isSubmitting = ref(false);
const isFetchingInboxes = ref(false);
const completionFailed = ref(false);
const channelsDialogRef = ref(null);
const whatsappInbox = computed(
  () =>
    createdInbox.value ||
    inboxes.value.find(inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP)
);
const connectedInbox = computed(() => whatsappInbox.value || inboxes.value[0]);
const isInitial = computed(
  () => state.value === 'idle' && !connectedInbox.value && isAvailable.value
);
const { width } = useWindowSize();
const isMobile = computed(
  () =>
    width.value < MOBILE_BREAKPOINT ||
    MOBILE_USER_AGENT.test(navigator.userAgent)
);
const metaTechProviderLive =
  window.chatwootConfig?.metaTechProviderLive === true;
const metaTechProviderBlack = new URL(
  '../../../assets/images/meta/meta_tech_provider_black.svg',
  import.meta.url
).href;
const metaTechProviderWhite = new URL(
  '../../../assets/images/meta/meta_tech_provider_white.svg',
  import.meta.url
).href;
// TEMPORAL: recreación vectorial del logo de WhatsApp Business hecha por el
// dueño. Reemplazar por el archivo oficial cuando esté disponible.
const whatsappBusinessLogo = new URL(
  '../../../assets/images/meta/whatsapp_business_temporal.svg',
  import.meta.url
).href;
const guideOpen = ref(false);
const trustPoints = computed(() => [
  t('ONBOARDING_WHATSAPP.TRUST.APP'),
  t('ONBOARDING_WHATSAPP.TRUST.OFFICIAL'),
  t('ONBOARDING_WHATSAPP.TRUST.BENEFITS'),
]);
const copyStatus = ref('');
const copyFailed = ref(false);
const isCopying = ref(false);
const copyLink = async () => {
  isCopying.value = true;
  try {
    await navigator.clipboard.writeText(window.location.href);
    copyFailed.value = false;
    copyStatus.value = t('ONBOARDING_WHATSAPP.MOBILE.COPIED');
    useAlert(copyStatus.value);
  } catch {
    copyFailed.value = true;
    copyStatus.value = t('ONBOARDING_WHATSAPP.MOBILE.COPY_ERROR');
    useAlert(copyStatus.value);
  } finally {
    isCopying.value = false;
  }
};
const isConnecting = computed(() => state.value === 'loading');
const buttonLabel = computed(() => {
  if (isConnecting.value) return t('ONBOARDING_WHATSAPP.CONNECTING');
  if (state.value === 'error') return t('ONBOARDING_WHATSAPP.RETRY');
  return t('ONBOARDING_WHATSAPP.CONNECT');
});

const refetchInboxes = async () => {
  isFetchingInboxes.value = true;
  try {
    await store.dispatch('inboxes/get');
  } catch {
    state.value = 'error';
  } finally {
    isFetchingInboxes.value = false;
  }
};
watch(
  isNewOnboarding,
  enabled => {
    if (!enabled) return;
    useTrack(ONBOARDING_EVENTS.INBOX_SETUP_VISITED);
    refetchInboxes();
  },
  { immediate: true }
);

const connectWhatsapp = async () => {
  if (!isAvailable.value || isConnecting.value || isSubmitting.value) return;
  state.value = 'loading';
  try {
    const credentials = await runEmbeddedSignup();
    if (!credentials) {
      state.value = 'cancelled';
      return;
    }
    createdInbox.value = await store.dispatch(
      'inboxes/createWhatsAppEmbeddedSignup',
      credentials
    );
    state.value = 'success';
  } catch {
    state.value = 'error';
  }
};

const completeOnboarding = async skipped => {
  if (isSubmitting.value) return;
  isSubmitting.value = true;
  completionFailed.value = false;
  try {
    await finishOnboarding({
      onboarding_step: 'inbox_setup',
      inbox_setup_result:
        !skipped && whatsappInbox.value ? 'whatsapp_connected' : 'skipped',
    });
    useTrack(
      skipped
        ? ONBOARDING_EVENTS.INBOX_SETUP_SKIPPED
        : ONBOARDING_EVENTS.INBOX_SETUP_COMPLETED
    );
    await store.dispatch('setUser');
    await router.push({
      name: isNewOnboarding.value ? 'onboarding_assistant' : 'home',
      params: { accountId: accountId.value },
    });
  } catch {
    completionFailed.value = true;
  } finally {
    isSubmitting.value = false;
  }
};
const openChannelsDialog = () => channelsDialogRef.value?.open();
</script>

<template>
  <LegacyInboxSetup v-if="currentAccount.id && !isNewOnboarding" />
  <AuthSplitLayout
    v-else-if="isNewOnboarding"
    :title="t('ONBOARDING_WHATSAPP.MARKETING.TITLE')"
    :subtitle="t('ONBOARDING_WHATSAPP.MARKETING.SUBTITLE')"
    onboarding
    scrollable
  >
    <AuthStepHeader
      :title="t('ONBOARDING_WHATSAPP.TITLE')"
      :subtitle="t('ONBOARDING_WHATSAPP.SUBTITLE')"
      :step-name="t('ONBOARDING_AUTH.WHATSAPP_STEP')"
      :current="CURRENT_STEP"
    >
      <template #brand>
        <div class="flex min-w-0 items-center justify-between gap-4">
          <img
            :src="whatsappBusinessLogo"
            alt="WhatsApp Business"
            data-testid="header-whatsapp-business"
            class="h-7 w-auto min-w-0 max-w-full object-contain object-left sm:h-10"
          />
          <div
            v-if="metaTechProviderLive"
            class="shrink-0 p-3 sm:p-5"
            data-testid="header-meta-tech-provider"
          >
            <img
              :src="metaTechProviderBlack"
              alt="Meta Tech Provider"
              class="h-auto w-20 sm:w-28 dark:hidden"
            />
            <img
              :src="metaTechProviderWhite"
              alt="Meta Tech Provider"
              class="hidden h-auto w-20 sm:w-28 dark:block"
            />
          </div>
        </div>
        <div
          v-if="isFetchingInboxes && !connectedInbox"
          role="status"
          class="space-y-2"
        >
          <span class="sr-only">{{ t('ONBOARDING_AUTH.LOADING') }}</span>
          <span
            class="block h-2 w-16 rounded-full bg-n-slate-5 motion-safe:animate-pulse"
            aria-hidden="true"
          />
          <span
            class="block h-2 w-12 rounded-full bg-n-slate-5 motion-safe:animate-pulse"
            aria-hidden="true"
          />
        </div>
      </template>
    </AuthStepHeader>

    <div
      v-if="connectedInbox"
      role="status"
      class="flex items-start gap-4 rounded-xl bg-n-slate-3 p-4 motion-safe:animate-fade-in-up motion-safe:[animation-duration:200ms]"
    >
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
        aria-hidden="true"
      >
        <span class="i-lucide-circle-check size-7" />
      </span>
      <div class="min-w-0 space-y-1">
        <p class="mb-0 font-medium text-n-slate-12">
          {{
            whatsappInbox
              ? t('ONBOARDING_WHATSAPP.CONNECTED')
              : t('ONBOARDING_WHATSAPP.OTHER_CONNECTED')
          }}
        </p>
        <p class="mb-0 break-words text-sm text-n-slate-11">
          {{ connectedInbox.name }}
        </p>
        <p v-if="whatsappInbox" class="mb-0 text-sm text-n-slate-11">
          {{ whatsappInbox.phone_number }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('ONBOARDING_WHATSAPP.AGENT_ASSIGNED') }}
        </p>
      </div>
    </div>
    <div
      v-else-if="!isAvailable"
      role="status"
      class="flex items-start gap-4 rounded-xl bg-n-slate-3 p-4 text-sm leading-6 text-n-slate-11"
    >
      <span class="i-lucide-info mt-0.5 size-5 shrink-0" aria-hidden="true" />
      <p class="mb-0 min-w-0">
        {{ t('ONBOARDING_WHATSAPP.UNAVAILABLE') }}
      </p>
    </div>
    <AuthFeedback v-else-if="state === 'error'" error>
      {{ t('ONBOARDING_WHATSAPP.ERROR') }}
    </AuthFeedback>
    <AuthFeedback v-else-if="state === 'cancelled'">
      {{ t('ONBOARDING_WHATSAPP.CANCELLED') }}
    </AuthFeedback>
    <AuthFeedback v-else-if="isConnecting">
      {{ t('ONBOARDING_WHATSAPP.CONNECTING') }}
    </AuthFeedback>

    <ol
      v-if="!connectedInbox && isAvailable"
      role="list"
      class="m-0 list-none space-y-4 p-0"
      data-testid="connection-steps"
    >
      <li
        v-for="step in connectionSteps"
        :key="step.icon"
        class="flex items-start gap-3"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
        >
          <span class="size-5" :class="step.icon" />
        </span>
        <p class="mb-0 min-w-0 pt-2 text-sm leading-6 text-n-slate-12">
          {{ step.label }}
        </p>
      </li>
    </ol>

    <div v-if="isInitial" class="mt-6 space-y-2">
      <details
        class="group rounded-xl border border-n-slate-7 px-4"
        data-testid="whatsapp-trust"
      >
        <summary
          class="flex min-h-12 cursor-pointer list-none items-center gap-2 py-3 text-sm font-medium leading-5 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
        >
          <span
            class="i-lucide-shield-check size-5 shrink-0 text-n-teal-11"
            aria-hidden="true"
          />
          {{ t('ONBOARDING_WHATSAPP.TRUST.SAFETY') }}
          <span
            class="i-lucide-chevron-down ms-auto size-4 shrink-0 group-open:rotate-180 motion-safe:transition-transform motion-safe:duration-150"
            aria-hidden="true"
          />
        </summary>
        <div class="space-y-3 pb-4">
          <h2 class="m-0 text-sm font-medium leading-5 text-n-slate-12">
            {{ t('ONBOARDING_WHATSAPP.TRUST.TITLE') }}
          </h2>
          <ul class="m-0 list-none space-y-2 p-0">
            <li
              v-for="point in trustPoints"
              :key="point"
              class="flex items-start gap-2 text-sm leading-6 text-n-slate-11"
            >
              <span
                class="i-lucide-check mt-1 size-4 shrink-0 text-n-teal-11"
                aria-hidden="true"
              />
              <span class="min-w-0">{{ point }}</span>
            </li>
            <li
              v-if="metaTechProviderLive"
              class="flex items-start gap-2 text-sm leading-6 text-n-slate-11"
            >
              <span
                class="i-lucide-check mt-1 size-4 shrink-0 text-n-teal-11"
                aria-hidden="true"
              />
              <span>{{ t('ONBOARDING_WHATSAPP.TRUST.PROVIDER') }}</span>
            </li>
          </ul>
        </div>
      </details>
      <button
        type="button"
        :class="AUTH_LINK_CLASS"
        data-testid="connection-guide"
        @click="guideOpen = true"
      >
        <span class="i-lucide-book-open size-4 shrink-0" aria-hidden="true" />
        {{ t('ONBOARDING_WHATSAPP.GUIDE.OPEN') }}
      </button>
    </div>
    <details
      v-if="isInitial && isMobile"
      class="mt-4 rounded-xl bg-n-slate-3 px-4 text-sm leading-6 text-n-slate-11"
      data-testid="mobile-notice"
    >
      <summary
        class="min-h-12 cursor-pointer py-3 font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand"
      >
        {{ t('ONBOARDING_WHATSAPP.MOBILE.TITLE') }}
      </summary>
      <div class="min-w-0 space-y-4 pb-4">
        <I18nT
          keypath="ONBOARDING_WHATSAPP.MOBILE.NOTICE"
          tag="p"
          class="mb-0"
          scope="global"
        >
          <template #code>
            <strong class="font-semibold text-n-slate-12">{{
              t('ONBOARDING_WHATSAPP.MOBILE.ENTER_CODE')
            }}</strong>
          </template>
        </I18nT>
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          class="text-start"
          data-testid="copy-link"
          :disabled="isCopying"
          :aria-busy="isCopying"
          @click="copyLink"
        >
          <Spinner v-if="isCopying" :size="16" aria-hidden="true" />
          {{ t('ONBOARDING_WHATSAPP.MOBILE.COPY') }}
        </button>
      </div>
      <AuthFeedback v-if="copyStatus" class="mb-4" :error="copyFailed">
        {{ copyStatus }}
      </AuthFeedback>
    </details>
    <WhatsappGuideDialog v-if="guideOpen" @close="guideOpen = false" />
    <InboxChannelsDialog
      ref="channelsDialogRef"
      :inboxes="inboxes"
      onboarding-v2
      @connected="refetchInboxes"
    />
    <template #footer>
      <AuthFeedback v-if="completionFailed" error>
        {{ t('ONBOARDING_WHATSAPP.COMPLETION_ERROR') }}
      </AuthFeedback>
      <AuthButton
        v-if="connectedInbox || isAvailable"
        type="button"
        :disabled="isConnecting || isSubmitting"
        :loading="isConnecting || isSubmitting"
        data-testid="primary"
        @click="connectedInbox ? completeOnboarding(false) : connectWhatsapp()"
      >
        {{ connectedInbox ? t('ONBOARDING_WHATSAPP.CONTINUE') : buttonLabel }}
      </AuthButton>
      <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
        <AuthButton
          v-if="!connectedInbox && !isAvailable"
          variant="secondary"
          :disabled="isSubmitting"
          data-testid="other-channel"
          @click="openChannelsDialog"
        >
          {{ t('ONBOARDING_WHATSAPP.OTHER_CHANNEL') }}
        </AuthButton>
        <button
          v-else
          type="button"
          :class="AUTH_LINK_CLASS"
          :disabled="isConnecting || isSubmitting"
          data-testid="other-channel"
          @click="openChannelsDialog"
        >
          {{ t('ONBOARDING_WHATSAPP.OTHER_CHANNEL') }}
        </button>
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          :disabled="isSubmitting"
          :aria-busy="isSubmitting"
          data-testid="skip"
          @click="completeOnboarding(true)"
        >
          <Spinner v-if="isSubmitting" :size="16" aria-hidden="true" />
          {{ t('ONBOARDING_WHATSAPP.SKIP') }}
        </button>
      </div>
    </template>
  </AuthSplitLayout>
  <Spinner v-else class="m-auto motion-reduce:animate-none" :size="32" />
</template>
