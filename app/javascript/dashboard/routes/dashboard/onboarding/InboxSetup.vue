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
import { useChannelConfig } from './inbox-setup/useChannelConfig';
import InboxChannelsDialog from './inbox-setup/InboxChannelsDialog.vue';
import LegacyInboxSetup from './LegacyInboxSetup.vue';

const WhatsappGuideDialog = defineAsyncComponent(
  () => import('./inbox-setup/WhatsappGuideDialog.vue')
);
const MOBILE_BREAKPOINT = 768;
const MOBILE_USER_AGENT = /Android|iPhone|iPad|iPod|Mobile/i;
const CURRENT_STEP = 3;
const TOTAL_STEPS = 5;
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
const guideOpen = ref(false);
const trustPoints = computed(() => [
  t('ONBOARDING_WHATSAPP.TRUST.APP'),
  t('ONBOARDING_WHATSAPP.TRUST.OFFICIAL'),
  t('ONBOARDING_WHATSAPP.TRUST.BENEFITS'),
]);
const copyLink = async () => {
  try {
    await navigator.clipboard.writeText(window.location.href);
    useAlert(t('ONBOARDING_WHATSAPP.MOBILE.COPIED'));
  } catch {
    useAlert(t('ONBOARDING_WHATSAPP.MOBILE.COPY_ERROR'));
  }
};
const isConnecting = computed(() => state.value === 'loading');
const buttonLabel = computed(() => {
  if (isConnecting.value) return t('ONBOARDING_WHATSAPP.CONNECTING');
  if (state.value === 'error') return t('ONBOARDING_WHATSAPP.RETRY');
  return t('ONBOARDING_WHATSAPP.CONNECT');
});

const refetchInboxes = async () => {
  try {
    await store.dispatch('inboxes/get');
  } catch {
    state.value = 'error';
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
    await router.push({ name: 'home', params: { accountId: accountId.value } });
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
    scrollable
  >
    <header class="mb-8">
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
        class="mb-6 flex gap-1.5"
      >
        <span
          v-for="step in TOTAL_STEPS"
          :key="step"
          class="h-1 flex-1 rounded-full"
          :class="step <= CURRENT_STEP ? 'bg-n-slate-12' : 'bg-n-slate-4'"
        />
      </div>
      <div class="mb-5 flex items-center justify-between gap-4">
        <span
          class="i-woot-whatsapp block size-10 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        <div
          v-if="metaTechProviderLive"
          class="shrink-0 p-5"
          data-testid="header-meta-tech-provider"
        >
          <img
            :src="metaTechProviderBlack"
            alt="Meta Tech Provider"
            class="h-auto w-28 dark:hidden"
          />
          <img
            :src="metaTechProviderWhite"
            alt="Meta Tech Provider"
            class="hidden h-auto w-28 dark:block"
          />
        </div>
      </div>
      <h2 class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl">
        {{ t('ONBOARDING_WHATSAPP.TITLE') }}
      </h2>
      <p class="mt-3 mb-0 text-base leading-7 text-n-slate-11">
        {{ t('ONBOARDING_WHATSAPP.SUBTITLE') }}
      </p>
    </header>

    <div
      v-if="connectedInbox"
      role="status"
      class="flex items-start gap-3 rounded-2xl bg-n-alpha-1 p-5"
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
      class="flex items-start gap-3 rounded-2xl bg-n-slate-3 p-5 text-sm leading-6 text-n-slate-11"
    >
      <span class="i-lucide-info mt-0.5 size-5 shrink-0" aria-hidden="true" />
      <p class="mb-0 min-w-0">
        {{ t('ONBOARDING_WHATSAPP.UNAVAILABLE') }}
      </p>
    </div>
    <p
      v-else-if="state === 'error'"
      role="alert"
      class="text-sm leading-6 text-n-ruby-11"
    >
      {{ t('ONBOARDING_WHATSAPP.ERROR') }}
    </p>
    <p
      v-else-if="state === 'cancelled'"
      role="status"
      class="text-sm leading-6 text-n-slate-11"
    >
      {{ t('ONBOARDING_WHATSAPP.CANCELLED') }}
    </p>
    <p
      v-else-if="isConnecting"
      role="status"
      class="text-sm leading-6 text-n-slate-11"
    >
      {{ t('ONBOARDING_WHATSAPP.CONNECTING') }}
    </p>

    <ol
      v-if="!connectedInbox && isAvailable"
      role="list"
      class="my-auto list-none space-y-6 py-4"
      data-testid="connection-steps"
    >
      <li
        v-for="step in connectionSteps"
        :key="step.icon"
        class="flex items-start gap-4"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
        >
          <span class="size-5" :class="step.icon" />
        </span>
        <p class="mb-0 min-w-0 pt-1.5 text-sm leading-6 text-n-slate-12">
          {{ step.label }}
        </p>
      </li>
    </ol>

    <section
      v-if="isInitial"
      class="space-y-4 py-4"
      data-testid="whatsapp-trust"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t('ONBOARDING_WHATSAPP.TRUST.TITLE') }}
      </h3>
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
      <button
        type="button"
        class="rounded-lg border border-n-slate-7 px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-testid="connection-guide"
        @click="guideOpen = true"
      >
        {{ t('ONBOARDING_WHATSAPP.GUIDE.OPEN') }}
      </button>
    </section>
    <aside
      v-if="isInitial && isMobile"
      class="mt-2 flex items-start gap-2 rounded-xl bg-n-slate-3 p-4 text-sm leading-6 text-n-slate-11"
      data-testid="mobile-notice"
    >
      <span class="i-lucide-info mt-1 size-4 shrink-0" aria-hidden="true" />
      <div class="min-w-0 space-y-3">
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
          class="rounded text-start font-medium text-n-slate-12 underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-testid="copy-link"
          @click="copyLink"
        >
          {{ t('ONBOARDING_WHATSAPP.MOBILE.COPY') }}
        </button>
      </div>
    </aside>
    <WhatsappGuideDialog v-if="guideOpen" @close="guideOpen = false" />
    <InboxChannelsDialog
      ref="channelsDialogRef"
      :inboxes="inboxes"
      onboarding-v2
      @connected="refetchInboxes"
    />
    <template #footer>
      <p
        v-if="completionFailed"
        role="alert"
        class="mb-3 text-sm text-n-ruby-11"
      >
        {{ t('ONBOARDING_WHATSAPP.COMPLETION_ERROR') }}
      </p>
      <button
        v-if="connectedInbox || isAvailable"
        type="button"
        class="flex h-14 w-full items-center justify-center gap-2 rounded-full bg-n-slate-12 px-6 text-base font-medium text-n-solid-1 transition-opacity hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isConnecting || isSubmitting"
        :aria-busy="isConnecting || isSubmitting"
        data-testid="primary"
        @click="connectedInbox ? completeOnboarding(false) : connectWhatsapp()"
      >
        <Spinner
          v-if="isConnecting || isSubmitting"
          :size="20"
          aria-hidden="true"
        />
        {{ connectedInbox ? t('ONBOARDING_WHATSAPP.CONTINUE') : buttonLabel }}
      </button>
      <div
        class="flex flex-wrap items-center justify-center gap-x-6 gap-y-3"
        :class="connectedInbox || isAvailable ? 'mt-5' : 'flex-col'"
      >
        <button
          type="button"
          class="hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          :class="
            !connectedInbox && !isAvailable
              ? 'flex h-14 w-full items-center justify-center rounded-full border border-n-slate-7 px-6 text-base font-medium text-n-slate-12 hover:enabled:bg-n-slate-3'
              : 'rounded text-sm text-n-slate-11'
          "
          :disabled="isConnecting || isSubmitting"
          data-testid="other-channel"
          @click="openChannelsDialog"
        >
          {{ t('ONBOARDING_WHATSAPP.OTHER_CHANNEL') }}
        </button>
        <button
          type="button"
          class="rounded text-sm text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          :disabled="isSubmitting"
          data-testid="skip"
          @click="completeOnboarding(true)"
        >
          {{ t('ONBOARDING_WHATSAPP.SKIP') }}
        </button>
      </div>
    </template>
  </AuthSplitLayout>
  <Spinner v-else class="m-auto" :size="32" />
</template>
