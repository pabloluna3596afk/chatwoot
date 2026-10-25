<script setup>
import {
  computed,
  defineAsyncComponent,
  onMounted,
  onUnmounted,
  ref,
  watch,
} from 'vue';
import { useI18n, Translation as I18nT } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useTrack } from 'dashboard/composables';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import OnboardingShell from './shared/OnboardingShell.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
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
const CURRENT_STEP = 2;
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
const windowWidth = ref(window.innerWidth);
const updateWindowWidth = () => {
  windowWidth.value = window.innerWidth;
};
onMounted(() => window.addEventListener('resize', updateWindowWidth));
onUnmounted(() => window.removeEventListener('resize', updateWindowWidth));
const isMobile = computed(
  () =>
    windowWidth.value < MOBILE_BREAKPOINT ||
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
const copyStatus = ref('');
const copyFailed = ref(false);
const isCopying = ref(false);
const copyLink = async () => {
  isCopying.value = true;
  try {
    await navigator.clipboard.writeText(window.location.href);
    copyFailed.value = false;
    copyStatus.value = t('ONBOARDING_WHATSAPP.MOBILE.COPIED');
  } catch {
    copyFailed.value = true;
    copyStatus.value = t('ONBOARDING_WHATSAPP.MOBILE.COPY_ERROR');
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
  <OnboardingShell
    v-else-if="isNewOnboarding"
    :current="CURRENT_STEP"
    :title="t('ONBOARDING_WHATSAPP.TITLE')"
    :subtitle="t('ONBOARDING_WHATSAPP.SUBTITLE')"
    :back-to="{ name: 'onboarding_account_details', params: { accountId } }"
    :back-disabled="isConnecting || isSubmitting"
  >
    <div
      class="mx-auto max-w-[40rem] rounded-xl border border-n-weak bg-n-solid-1 p-5 shadow-sm sm:p-8 dark:bg-n-solid-3"
    >
      <img
        :src="whatsappBusinessLogo"
        alt="WhatsApp Business"
        data-testid="header-whatsapp-business"
        class="mb-7 h-auto w-60 max-w-full"
      />
      <p v-if="isFetchingInboxes" role="status" class="text-sm text-n-slate-11">
        {{ t('ONBOARDING_AUTH.LOADING') }}
      </p>
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

      <div
        v-if="!connectedInbox && isAvailable"
        class="space-y-4"
        data-testid="connection-steps"
      >
        <h2 class="m-0 text-base font-medium">
          {{ t('ONBOARDING_WHATSAPP.PREPARE') }}
        </h2>
        <ul class="m-0 list-none space-y-3 p-0">
          <li
            v-for="step in connectionSteps"
            :key="step.icon"
            class="flex items-start gap-3 text-base leading-6"
          >
            <span
              class="i-lucide-check mt-1 size-4 shrink-0 text-n-teal-11"
              aria-hidden="true"
            /><span>{{ step.label }}</span>
          </li>
        </ul>
        <p class="m-0 pt-2 text-sm text-n-slate-11">
          {{ t('ONBOARDING_WHATSAPP.AUTHORIZATION') }}
        </p>
      </div>
      <AuthButton
        v-if="!connectedInbox && isAvailable"
        class="mt-5"
        :loading="isConnecting"
        :disabled="isConnecting || isSubmitting"
        data-testid="primary"
        @click="connectWhatsapp"
      >
        {{ buttonLabel
        }}<span class="i-lucide-external-link size-4" aria-hidden="true" />
      </AuthButton>
      <div
        v-if="metaTechProviderLive"
        class="flex justify-center p-7"
        data-testid="header-meta-tech-provider"
      >
        <img
          :src="metaTechProviderBlack"
          alt="Meta Tech Provider"
          class="h-auto w-40 dark:hidden"
        />
        <img
          :src="metaTechProviderWhite"
          alt="Meta Tech Provider"
          class="hidden h-auto w-40 dark:block"
        />
      </div>
      <div class="mt-6 space-y-2 border-t border-n-weak pt-5 text-center">
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          :disabled="isSubmitting"
          :aria-busy="isSubmitting"
          data-testid="skip"
          @click="completeOnboarding(true)"
        >
          {{ t('ONBOARDING_WHATSAPP.SKIP') }}
        </button>
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{ t('ONBOARDING_WHATSAPP.RESUME') }}
        </p>
      </div>
      <details
        v-if="state === 'error' || state === 'cancelled' || !isAvailable"
        class="mt-4 text-sm text-n-slate-11"
      >
        <summary class="cursor-pointer py-3">
          {{ t('ONBOARDING_WHATSAPP.GUIDE.OPEN') }}
        </summary>
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          data-testid="connection-guide"
          @click="guideOpen = true"
        >
          {{ t('ONBOARDING_WHATSAPP.GUIDE.OPEN') }}
        </button>
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          data-testid="other-channel"
          @click="openChannelsDialog"
        >
          {{ t('ONBOARDING_WHATSAPP.OTHER_CHANNEL') }}
        </button>
      </details>
      <details
        v-if="isInitial && isMobile"
        class="mt-4 text-sm leading-6 text-n-slate-11"
        data-testid="mobile-notice"
      >
        <summary class="min-h-11 cursor-pointer py-3">
          {{ t('ONBOARDING_WHATSAPP.MOBILE.TITLE') }}
        </summary>
        <I18nT
          keypath="ONBOARDING_WHATSAPP.MOBILE.NOTICE"
          tag="p"
          scope="global"
        >
          <template #code>
            <strong>{{ t('ONBOARDING_WHATSAPP.MOBILE.ENTER_CODE') }}</strong>
          </template>
        </I18nT>
        <button
          type="button"
          :class="AUTH_LINK_CLASS"
          data-testid="copy-link"
          :disabled="isCopying"
          :aria-busy="isCopying"
          @click="copyLink"
        >
          {{ t('ONBOARDING_WHATSAPP.MOBILE.COPY') }}
        </button>
        <AuthFeedback v-if="copyStatus" :error="copyFailed">
          {{ copyStatus }}
        </AuthFeedback>
      </details>
    </div>
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
        v-if="connectedInbox"
        :disabled="isSubmitting"
        :loading="isSubmitting"
        data-testid="primary"
        @click="completeOnboarding(false)"
      >
        {{ t('ONBOARDING_WHATSAPP.CONTINUE') }}
      </AuthButton>
    </template>
  </OnboardingShell>
  <Spinner v-else class="m-auto motion-reduce:animate-none" :size="32" />
</template>
