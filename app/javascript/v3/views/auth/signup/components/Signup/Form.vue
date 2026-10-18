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
import AuthField from '../../../../../components/Auth/AuthField.vue';
import AuthButton from '../../../../../components/Auth/AuthButton.vue';
import AuthFeedback from '../../../../../components/Auth/AuthFeedback.vue';
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
const registrationError = ref('');

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
const passwordError = computed(() => {
  if (!v$.value.credentials.password.$error) return '';
  return credentials.password.length < MIN_PASSWORD_LENGTH
    ? t('REGISTER.PASSWORD.ERROR')
    : t('REGISTER.PASSWORD.IS_INVALID_PASSWORD');
});

const performRegistration = async () => {
  isSignupInProgress.value = true;
  registrationError.value = '';
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
    registrationError.value = errorMessage;
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
  registrationError.value = t('REGISTER.CAPTCHA.ERROR');
  useAlert(t('REGISTER.CAPTCHA.ERROR'));
};
</script>

<template>
  <div class="flex-1">
    <form class="space-y-4" @submit.prevent="submit">
      <AuthField
        id="email_address"
        v-model="credentials.email"
        type="email"
        name="email_address"
        autocomplete="email"
        required
        :label="$t('REGISTER.EMAIL.LABEL')"
        :placeholder="$t('REGISTER.EMAIL.PLACEHOLDER')"
        :error="v$.credentials.email.$error ? $t('REGISTER.EMAIL.ERROR') : ''"
        @blur="v$.credentials.email.$touch"
      />
      <div>
        <AuthField
          id="password"
          v-model="credentials.password"
          type="password"
          name="password"
          autocomplete="new-password"
          required
          describedby="signup-password-requirements"
          :label="$t('REGISTER.PASSWORD.LABEL')"
          :placeholder="$t('REGISTER.PASSWORD.PLACEHOLDER')"
          :error="passwordError"
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
      <AuthFeedback v-if="registrationError" error>
        {{ registrationError }}
      </AuthFeedback>
      <AuthButton
        type="submit"
        data-testid="submit_button"
        :aria-label="$t('REGISTER.SUBMIT')"
        :loading="isSignupInProgress"
        :disabled="isSignupInProgress || !isFormValid"
      >
        {{ $t('REGISTER.SUBMIT') }}
      </AuthButton>
    </form>
    <div v-if="showGoogleOAuth" class="mt-6 space-y-4">
      <SimpleDivider
        :label="$t('REGISTER.OR')"
        bg="bg-n-solid-1 dark:bg-n-background"
        class="[&_.border-t]:border-solid [&_.border-t]:border-n-slate-7 [&_span]:text-n-slate-11"
      />
      <GoogleOAuthButton
        class="[&>a]:!h-auto [&>a]:min-h-12 [&>a]:!rounded-xl [&>a]:!border-n-slate-9 [&>a]:dark:!border-n-slate-10 [&>a]:!bg-n-solid-1 [&>a]:py-3 [&>a]:!text-n-slate-12 motion-reduce:[&>a]:transition-none [&>a]:dark:!bg-n-solid-3 [&>a]:hover:!bg-n-slate-3"
      >
        {{ $t('REGISTER.OAUTH.GOOGLE_SIGNUP') }}
      </GoogleOAuthButton>
      <p class="m-0 text-center text-sm leading-6 text-n-slate-11">
        {{ $t('REGISTER.OAUTH.PASSWORD_NOTICE') }}
      </p>
    </div>
    <p
      class="mt-6 mb-0 text-center text-sm leading-6 text-n-slate-11 [&>a]:inline-flex [&>a]:min-h-11 [&>a]:items-center [&>a]:rounded [&>a]:font-medium [&>a]:text-n-slate-12 [&>a]:underline [&>a]:underline-offset-4 [&>a]:focus-visible:outline [&>a]:focus-visible:outline-2 [&>a]:focus-visible:outline-n-brand"
      v-html="sanitizedTermsLink"
    />
  </div>
</template>
