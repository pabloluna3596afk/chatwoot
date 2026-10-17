<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { email as isEmail } from '@vuelidate/validators';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import { DEFAULT_REDIRECT_URL } from 'dashboard/constants/globals';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import FormInput from '../../../components/Form/Input.vue';
import { resendConfirmation, verifyPasswordToken } from '../../../api/auth';

const props = defineProps({
  confirmationToken: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const store = useStore();
const globalConfig = computed(() => store.getters['globalConfig/get']);
const hasConfirmationError = ref(false);
const email = ref('');
const isResendingEmail = ref(false);
const resendStatus = ref('');
const hCaptcha = ref(null);
const isEmailValid = computed(
  () => Boolean(email.value) && isEmail.$validator(email.value)
);

onMounted(async () => {
  try {
    await verifyPasswordToken({ confirmationToken: props.confirmationToken });
    window.location = DEFAULT_REDIRECT_URL;
  } catch {
    hasConfirmationError.value = true;
  }
});

const performResend = async (token = '') => {
  try {
    await resendConfirmation({
      email: email.value,
      hCaptchaClientResponse: token,
    });
    resendStatus.value = 'REGISTER.VERIFY_EMAIL.RESEND_SUCCESS';
  } catch {
    resendStatus.value = 'REGISTER.VERIFY_EMAIL.RESEND_ERROR';
  } finally {
    isResendingEmail.value = false;
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
    }
  }
};

const handleResendEmail = () => {
  if (isResendingEmail.value || !isEmailValid.value) return;
  isResendingEmail.value = true;
  resendStatus.value = '';
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performResend();
  }
};

const onCaptchaError = () => {
  isResendingEmail.value = false;
  resendStatus.value = 'REGISTER.CAPTCHA.ERROR';
  hCaptcha.value.reset();
};
</script>

<template>
  <main
    class="flex items-center justify-center min-h-screen h-full bg-n-background w-full"
  >
    <section v-if="hasConfirmationError" class="w-full max-w-lg p-8 space-y-4">
      <div role="alert">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('REGISTER.CONFIRMATION.ERROR_TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ t('REGISTER.CONFIRMATION.ERROR_DESCRIPTION') }}
        </p>
      </div>
      <router-link :to="{ name: 'login' }" class="text-n-blue-11">
        {{ t('REGISTER.CONFIRMATION.LOGIN') }}
      </router-link>
      <form class="space-y-4" @submit.prevent="handleResendEmail">
        <FormInput
          v-model="email"
          type="email"
          name="email"
          autocomplete="email"
          required
          :disabled="isResendingEmail"
          :label="t('REGISTER.EMAIL.LABEL')"
          :placeholder="t('REGISTER.EMAIL.PLACEHOLDER')"
        />
        <VueHcaptcha
          v-if="globalConfig.hCaptchaSiteKey"
          ref="hCaptcha"
          size="invisible"
          :sitekey="globalConfig.hCaptchaSiteKey"
          @verify="performResend"
          @error="onCaptchaError"
          @expired="onCaptchaError"
          @challenge-expired="onCaptchaError"
          @closed="onCaptchaError"
        />
        <NextButton
          type="submit"
          class="w-full"
          :label="t('REGISTER.CONFIRMATION.RESEND')"
          :disabled="isResendingEmail || !isEmailValid"
          :is-loading="isResendingEmail"
        />
        <p v-if="resendStatus" role="status" class="text-sm text-n-slate-11">
          {{ t(resendStatus) }}
        </p>
      </form>
    </section>
    <template v-else>
      <Spinner color-scheme="primary" size="" />
      <div class="ms-2 text-n-slate-11">{{ t('CONFIRM_EMAIL') }}</div>
    </template>
  </main>
</template>
