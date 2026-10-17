<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import metaTechProviderBlack from 'dashboard/assets/images/meta/meta_tech_provider_black.svg';
import metaTechProviderWhite from 'dashboard/assets/images/meta/meta_tech_provider_white.svg';

const emit = defineEmits(['close']);
const { t } = useI18n();
const dialogRef = ref(null);
const metaTechProviderLive =
  window.chatwootConfig?.metaTechProviderLive === true;
const videoUrl = window.chatwootConfig?.whatsappGuideVideoUrl;
const steps = computed(() => [
  t('ONBOARDING_WHATSAPP.GUIDE.STEPS.LOGIN'),
  t('ONBOARDING_WHATSAPP.GUIDE.STEPS.NUMBER'),
  t('ONBOARDING_WHATSAPP.GUIDE.STEPS.VERIFY'),
]);
const changes = computed(() => [
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.HISTORY'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.GROUPS'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.MESSAGES'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.ACTIVITY'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.VERSION'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.THROUGHPUT'),
  t('ONBOARDING_WHATSAPP.GUIDE.CHANGES.DISCONNECT'),
]);
const officialLinks = computed(() => [
  {
    label: t('ONBOARDING_WHATSAPP.GUIDE.LINKS.COEXISTENCE'),
    url: 'https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users',
  },
  {
    label: t('ONBOARDING_WHATSAPP.GUIDE.LINKS.TECH_PROVIDER'),
    url: 'https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers',
  },
]);
onMounted(() => dialogRef.value.open());
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('ONBOARDING_WHATSAPP.GUIDE.TITLE')"
    :cancel-button-label="t('ONBOARDING_WHATSAPP.GUIDE.CLOSE')"
    :show-confirm-button="false"
    width="xl"
    body-scroll
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-6 text-sm leading-6 text-n-slate-11">
      <ol class="m-0 list-none space-y-4 p-0" data-testid="guide-steps">
        <li
          v-for="(step, index) in steps"
          :key="step"
          class="flex items-start gap-3"
        >
          <span
            class="flex size-7 shrink-0 items-center justify-center rounded-full bg-n-teal-3 font-semibold text-n-teal-11"
            aria-hidden="true"
          >
            {{ index + 1 }}
          </span>
          <p class="mb-0 min-w-0">
            {{ step }}
          </p>
        </li>
      </ol>
      <section>
        <h4 class="mb-3 text-base font-semibold text-n-slate-12">
          {{ t('ONBOARDING_WHATSAPP.GUIDE.CHANGES_TITLE') }}
        </h4>
        <ul class="m-0 list-disc space-y-2 ps-5" data-testid="guide-changes">
          <li v-for="change in changes" :key="change">
            {{ change }}
          </li>
        </ul>
      </section>
      <section v-if="videoUrl" data-testid="guide-video">
        <h4 class="mb-3 text-base font-semibold text-n-slate-12">
          {{ t('ONBOARDING_WHATSAPP.GUIDE.VIDEO') }}
        </h4>
        <slot name="video" :url="videoUrl">
          <video
            :src="videoUrl"
            :aria-label="t('ONBOARDING_WHATSAPP.GUIDE.VIDEO')"
            controls
            preload="none"
            class="aspect-video w-full rounded-xl bg-n-slate-3"
          />
        </slot>
      </section>
      <nav
        :aria-label="t('ONBOARDING_WHATSAPP.GUIDE.SOURCES')"
        class="flex flex-col items-start gap-2"
      >
        <a
          v-for="link in officialLinks"
          :key="link.label"
          :href="link.url"
          target="_blank"
          rel="noopener noreferrer"
          class="rounded text-n-slate-12 underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ link.label }}
        </a>
      </nav>
      <div
        v-if="metaTechProviderLive"
        class="flex justify-center p-8"
        data-testid="meta-tech-provider"
      >
        <img
          :src="metaTechProviderBlack"
          :alt="t('ONBOARDING_WHATSAPP.GUIDE.BADGE_ALT')"
          class="h-auto w-40 shrink-0 dark:hidden"
        />
        <img
          :src="metaTechProviderWhite"
          :alt="t('ONBOARDING_WHATSAPP.GUIDE.BADGE_ALT')"
          class="hidden h-auto w-40 shrink-0 dark:block"
        />
      </div>
    </div>
  </Dialog>
</template>
