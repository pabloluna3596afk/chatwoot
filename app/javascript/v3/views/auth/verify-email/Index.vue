<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import { resendConfirmation } from '../../../api/auth';

const props = defineProps({
  email: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();

if (!props.email) {
  router.push({ name: 'login' });
}

const globalConfig = computed(() => store.getters['globalConfig/get']);
const isResendingEmail = ref(false);
const hCaptcha = ref(null);
let captchaToken = '';

const performResend = async () => {
  isResendingEmail.value = true;
  try {
    await resendConfirmation({
      email: props.email,
      hCaptchaClientResponse: captchaToken,
    });
    useAlert(t('REGISTER.VERIFY_EMAIL.RESEND_SUCCESS'));
  } catch {
    useAlert(t('REGISTER.VERIFY_EMAIL.RESEND_ERROR'));
  } finally {
    isResendingEmail.value = false;
    captchaToken = '';
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
    }
  }
};

const handleResendEmail = () => {
  if (isResendingEmail.value) return;
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performResend();
  }
};

const onCaptchaVerified = token => {
  captchaToken = token;
  performResend();
};

const onCaptchaError = () => {
  isResendingEmail.value = false;
  captchaToken = '';
  hCaptcha.value.reset();
};
</script>

<template>
  <AuthSplitLayout
    :title="$t('REGISTER.MARKETING.TITLE')"
    :subtitle="$t('REGISTER.MARKETING.SUBTITLE')"
  >
    <div class="text-center">
      <div class="mb-8">
        <span
          class="i-lucide-mail mx-auto mb-6 block size-12 text-n-slate-12"
          aria-hidden="true"
        />
        <h2
          class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl"
        >
          {{ $t('REGISTER.VERIFY_EMAIL.TITLE') }}
        </h2>
        <p class="mt-3 break-words text-sm text-n-slate-11">
          {{ $t('REGISTER.VERIFY_EMAIL.DESCRIPTION', { email }) }}
        </p>
      </div>
      <div class="space-y-4">
        <VueHcaptcha
          v-if="globalConfig.hCaptchaSiteKey"
          ref="hCaptcha"
          size="invisible"
          :sitekey="globalConfig.hCaptchaSiteKey"
          @verify="onCaptchaVerified"
          @error="onCaptchaError"
          @expired="onCaptchaError"
          @challenge-expired="onCaptchaError"
          @closed="onCaptchaError"
        />
        <button
          type="button"
          data-testid="resend_email_button"
          class="flex h-14 w-full items-center justify-center rounded-full bg-n-slate-12 px-6 text-base font-medium text-n-solid-1 transition-opacity hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-wait"
          :aria-label="$t('REGISTER.VERIFY_EMAIL.RESEND')"
          :aria-busy="isResendingEmail"
          :disabled="isResendingEmail"
          @click="handleResendEmail"
        >
          <Spinner v-if="isResendingEmail" :size="20" aria-hidden="true" />
          <span v-else>{{ $t('REGISTER.VERIFY_EMAIL.RESEND') }}</span>
        </button>
        <router-link
          to="/app/login"
          class="inline-block text-sm font-medium text-n-brand hover:underline focus-visible:underline"
        >
          {{ $t('REGISTER.SIGN_IN') }}
        </router-link>
      </div>
    </div>
  </AuthSplitLayout>
</template>
