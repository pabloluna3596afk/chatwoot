<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import AuthStepHeader from '../../../components/Auth/AuthStepHeader.vue';
import AuthButton from '../../../components/Auth/AuthButton.vue';
import AuthFeedback from '../../../components/Auth/AuthFeedback.vue';
import { AUTH_LINK_CLASS } from '../../../components/Auth/authStyles';
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
const resendStatus = ref('');
const resendFailed = ref(false);
const hCaptcha = ref(null);
let captchaToken = '';

const performResend = async () => {
  isResendingEmail.value = true;
  try {
    await resendConfirmation({
      email: props.email,
      hCaptchaClientResponse: captchaToken,
    });
    resendStatus.value = t('REGISTER.VERIFY_EMAIL.RESEND_SUCCESS');
    useAlert(t('REGISTER.VERIFY_EMAIL.RESEND_SUCCESS'));
  } catch {
    resendFailed.value = true;
    resendStatus.value = t('REGISTER.VERIFY_EMAIL.RESEND_ERROR');
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
  isResendingEmail.value = true;
  resendStatus.value = '';
  resendFailed.value = false;
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
  resendFailed.value = true;
  resendStatus.value = t('REGISTER.CAPTCHA.ERROR');
};
</script>

<template>
  <AuthSplitLayout
    :title="$t('REGISTER.MARKETING.TITLE')"
    :subtitle="$t('REGISTER.MARKETING.SUBTITLE')"
    onboarding
  >
    <AuthStepHeader
      :title="$t('REGISTER.VERIFY_EMAIL.TITLE')"
      :subtitle="$t('REGISTER.VERIFY_EMAIL.DESCRIPTION', { email })"
      :step-name="$t('REGISTER.VERIFY_EMAIL.TITLE')"
      :current="1"
    >
      <template #brand>
        <span
          class="i-lucide-mail block size-10 text-n-slate-12"
          aria-hidden="true"
        />
      </template>
    </AuthStepHeader>
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
      <AuthFeedback v-if="resendStatus" :error="resendFailed">
        {{ resendStatus }}
      </AuthFeedback>
      <AuthButton
        type="button"
        data-testid="resend_email_button"
        :aria-label="$t('REGISTER.VERIFY_EMAIL.RESEND')"
        :loading="isResendingEmail"
        :disabled="isResendingEmail"
        @click="handleResendEmail"
      >
        {{ $t('REGISTER.VERIFY_EMAIL.RESEND') }}
      </AuthButton>
      <div class="text-center">
        <router-link to="/app/login" :class="AUTH_LINK_CLASS">
          {{ $t('REGISTER.SIGN_IN') }}
        </router-link>
      </div>
    </div>
  </AuthSplitLayout>
</template>
