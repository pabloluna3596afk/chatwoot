<script setup>
import { ref, computed, reactive } from 'vue';
import DOMPurify from 'dompurify';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, email } from '@vuelidate/validators';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import FormInput from '../../../../../components/Form/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PasswordRequirements from './PasswordRequirements.vue';
import { isValidPassword } from 'shared/helpers/Validators';
import GoogleOAuthButton from '../../../../../components/GoogleOauth/Button.vue';
import SimpleDivider from '../../../../../components/Divider/SimpleDivider.vue';
import { register } from '../../../../../api/auth';

const MIN_PASSWORD_LENGTH = 6;

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const hCaptcha = ref(null);
const isSignupInProgress = ref(false);

const credentials = reactive({
  email: '',
  password: '',
  hCaptchaClientResponse: '',
});

const rules = {
  credentials: {
    email: {
      required,
      email,
    },
    password: {
      required,
      isValidPassword,
      minLength: minLength(MIN_PASSWORD_LENGTH),
    },
  },
};

const v$ = useVuelidate(rules, { credentials });

const globalConfig = computed(() => store.getters['globalConfig/get']);

const termsLink = computed(() =>
  t('REGISTER.TERMS_ACCEPT')
    .replace('https://www.chatwoot.com/terms', globalConfig.value.termsURL)
    .replace(
      'https://www.chatwoot.com/privacy-policy',
      globalConfig.value.privacyURL
    )
);

const sanitizedTermsLink = computed(() => DOMPurify.sanitize(termsLink.value));

const allowedLoginMethods = computed(
  () => window.chatwootConfig.allowedLoginMethods || ['email']
);

const showGoogleOAuth = computed(
  () =>
    allowedLoginMethods.value.includes('google_oauth') &&
    Boolean(window.chatwootConfig.googleOAuthClientId)
);

const isFormValid = computed(() => !v$.value.$invalid);

const performRegistration = async () => {
  isSignupInProgress.value = true;
  try {
    await register(credentials);
    router.push({
      name: 'auth_verify_email',
      state: { email: credentials.email },
    });
  } catch (error) {
    const errorMessage =
      error?.message === 'Invalid Captcha'
        ? t('REGISTER.CAPTCHA.ERROR')
        : error?.message || t('REGISTER.API.ERROR_MESSAGE');
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
      credentials.hCaptchaClientResponse = '';
    }
    useAlert(errorMessage);
  } finally {
    isSignupInProgress.value = false;
  }
};

const submit = () => {
  if (isSignupInProgress.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) return;
  isSignupInProgress.value = true;
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performRegistration();
  }
};

const onRecaptchaVerified = token => {
  credentials.hCaptchaClientResponse = token;
  performRegistration();
};

const onCaptchaError = () => {
  isSignupInProgress.value = false;
  credentials.hCaptchaClientResponse = '';
  hCaptcha.value.reset();
  useAlert(t('REGISTER.CAPTCHA.ERROR'));
};
</script>

<template>
  <div class="flex-1">
    <form class="space-y-3" @submit.prevent="submit">
      <FormInput
        v-model="credentials.email"
        type="email"
        name="email_address"
        autocomplete="email"
        required
        label-sr-only
        outlined
        :label="$t('REGISTER.EMAIL.LABEL')"
        :placeholder="$t('REGISTER.EMAIL.PLACEHOLDER')"
        :has-error="v$.credentials.email.$error"
        :error-message="$t('REGISTER.EMAIL.ERROR')"
        @blur="v$.credentials.email.$touch"
      />
      <div>
        <FormInput
          v-model="credentials.password"
          type="password"
          name="password"
          autocomplete="new-password"
          required
          label-sr-only
          outlined
          aria-describedby="signup-password-requirements"
          :label="$t('REGISTER.PASSWORD.LABEL')"
          :placeholder="$t('REGISTER.PASSWORD.PLACEHOLDER')"
          :has-error="v$.credentials.password.$error"
          @blur="v$.credentials.password.$touch"
        />
        <PasswordRequirements
          id="signup-password-requirements"
          :password="credentials.password"
        />
      </div>
      <VueHcaptcha
        v-if="globalConfig.hCaptchaSiteKey"
        ref="hCaptcha"
        size="invisible"
        :sitekey="globalConfig.hCaptchaSiteKey"
        @verify="onRecaptchaVerified"
        @error="onCaptchaError"
        @expired="onCaptchaError"
        @challenge-expired="onCaptchaError"
        @closed="onCaptchaError"
      />
      <button
        type="submit"
        data-testid="submit_button"
        class="flex h-14 w-full items-center justify-center rounded-full bg-n-slate-12 px-6 text-base font-medium text-n-solid-1 transition-opacity hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
        :aria-label="$t('REGISTER.SUBMIT')"
        :aria-busy="isSignupInProgress"
        :disabled="isSignupInProgress || !isFormValid"
      >
        <Spinner v-if="isSignupInProgress" :size="20" aria-hidden="true" />
        <span v-else>{{ $t('REGISTER.SUBMIT') }}</span>
      </button>
    </form>
    <div v-if="showGoogleOAuth" class="mt-6 space-y-3">
      <SimpleDivider
        :label="$t('REGISTER.OR')"
        bg="bg-n-solid-1 dark:bg-n-background"
      />
      <GoogleOAuthButton>
        {{ $t('REGISTER.OAUTH.GOOGLE_SIGNUP') }}
      </GoogleOAuthButton>
      <p class="text-center text-xs text-n-slate-11">
        {{ $t('REGISTER.OAUTH.PASSWORD_NOTICE') }}
      </p>
    </div>
    <p
      class="text-sm mt-6 mb-0 text-center text-n-slate-11 [&>a]:text-n-blue-10 [&>a]:font-medium [&>a]:hover:text-n-blue-11"
      v-html="sanitizedTermsLink"
    />
  </div>
</template>
