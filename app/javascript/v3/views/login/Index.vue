<script setup>
import { computed, nextTick, onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { required, email as emailValidator } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { login } from '../../api/auth';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { SESSION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import SessionLimitOverlay from 'dashboard/components/auth/SessionLimitOverlay.vue';
import loginHero from 'assets/images/auth/login-hero.png';

const props = defineProps({
  ssoAuthToken: { type: String, default: '' },
  ssoAccountId: { type: String, default: '' },
  ssoConversationId: { type: String, default: '' },
  email: { type: String, default: '' },
  authError: { type: String, default: '' },
});

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';
const AUTH_ERROR_TOAST_DURATION = 6000;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { replaceInstallationName } = useBranding();
const globalConfig = useMapGetter('globalConfig/get');
const credentials = reactive({ email: '', password: '' });
const loginApi = reactive({
  message: '',
  showLoading: false,
  hasErrored: false,
});
const mfaRequired = ref(false);
const mfaToken = ref(null);
const sessionsLimitReached = ref(false);
const limitedSessions = ref([]);
const v$ = useVuelidate(
  {
    credentials: {
      password: { required },
      email: { required, email: emailValidator },
    },
  },
  { credentials }
);

const allowedLoginMethods = computed(
  () => window.chatwootConfig.allowedLoginMethods || ['email']
);
const showGoogleOAuth = computed(
  () =>
    allowedLoginMethods.value.includes('google_oauth') &&
    Boolean(window.chatwootConfig.googleOAuthClientId)
);
const showSignupLink = computed(
  () => window.chatwootConfig.signupEnabled === 'true'
);
const showSamlLogin = computed(() =>
  allowedLoginMethods.value.includes('saml')
);
const isStaging = computed(
  () => globalConfig.value.deploymentEnv === 'staging'
);

function getAuthErrorMessage() {
  switch (props.authError) {
    case 'no-account-found':
      return t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
    case 'business-account-only':
      return t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
    case 'saml-authentication-failed':
    case 'saml-not-enabled':
      return t('LOGIN.SAML.API.ERROR_MESSAGE');
    default:
      return t('LOGIN.API.UNAUTH');
  }
}

onMounted(() => {
  if (!props.authError) return;

  // Wait for the sibling snackbar to subscribe before showing the OAuth error.
  nextTick(() => {
    useAlert(getAuthErrorMessage(), { duration: AUTH_ERROR_TOAST_DURATION });
    const clearAuthError = () => {
      router.replace({ query: { ...route.query, error: undefined } });
    };
    if (window.requestIdleCallback) {
      window.requestIdleCallback(clearAuthError);
    } else {
      setTimeout(clearAuthError, 0);
    }
  });
});

function showAlertMessage(message) {
  loginApi.showLoading = false;
  loginApi.message = message;
  useAlert(message);
}

function handleImpersonation() {
  const urlParams = new URLSearchParams(window.location.search);
  if (urlParams.get(IMPERSONATION_URL_SEARCH_KEY)) {
    SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
  }
}

function getLoginCredentials() {
  return {
    email: props.email ? decodeURIComponent(props.email) : credentials.email,
    password: credentials.password,
    sso_auth_token: props.ssoAuthToken,
    ssoAccountId: props.ssoAccountId,
    ssoConversationId: props.ssoConversationId,
  };
}

function submitLogin() {
  loginApi.hasErrored = false;
  loginApi.showLoading = true;
  const loginCredentials = getLoginCredentials();

  login(loginCredentials)
    .then(result => {
      if (result?.mfaRequired) {
        loginApi.showLoading = false;
        mfaRequired.value = true;
        mfaToken.value = result.mfaToken;
        return;
      }
      if (result?.sessionsLimitReached) {
        loginApi.showLoading = false;
        sessionsLimitReached.value = true;
        limitedSessions.value = result.sessions;
        AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
        return;
      }
      handleImpersonation();
      showAlertMessage(t('LOGIN.API.SUCCESS_MESSAGE'));
    })
    .catch(response => {
      if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
        loginApi.showLoading = false;
        router.push({
          name: 'auth_verify_email',
          state: { email: loginCredentials.email },
        });
        return;
      }
      if (props.email) {
        window.location = '/app/login';
      }
      loginApi.hasErrored = true;
      showAlertMessage(response?.message || t('LOGIN.API.UNAUTH'));
    });
}

function submitFormLogin() {
  if (v$.value.credentials.email.$invalid && !props.email) {
    showAlertMessage(t('LOGIN.EMAIL.ERROR'));
    return;
  }
  submitLogin();
}

function handleMfaVerified() {
  handleImpersonation();
  window.location = '/app';
}

function handleMfaCancel() {
  mfaRequired.value = false;
  mfaToken.value = null;
  credentials.password = '';
}

function retryLoginWithParams(extraParams) {
  sessionsLimitReached.value = false;
  limitedSessions.value = [];
  loginApi.showLoading = true;
  login({ ...getLoginCredentials(), ...extraParams })
    .then(result => {
      if (result?.sessionsLimitReached) {
        loginApi.showLoading = false;
        sessionsLimitReached.value = true;
        limitedSessions.value = result.sessions;
        AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
        return;
      }
      handleImpersonation();
      showAlertMessage(t('LOGIN.API.SUCCESS_MESSAGE'));
    })
    .catch(response => {
      loginApi.hasErrored = true;
      showAlertMessage(response?.message || t('LOGIN.API.UNAUTH'));
    });
}

function handleSessionRevoke(sessionId) {
  retryLoginWithParams({ revoke_session_id: sessionId });
}

function handleSessionRevokeAll() {
  retryLoginWithParams({ revoke_all_sessions: true });
}

function handleSessionLimitCancel() {
  sessionsLimitReached.value = false;
  limitedSessions.value = [];
  credentials.password = '';
}

if (props.ssoAuthToken) {
  submitLogin();
}
</script>

<template>
  <main class="flex min-h-screen w-full bg-n-solid-1 dark:bg-n-background">
    <aside class="relative hidden min-h-screen w-1/2 overflow-hidden lg:block">
      <img
        :src="loginHero"
        alt=""
        aria-hidden="true"
        class="absolute inset-0 size-full object-cover object-right"
      />
      <div
        class="absolute inset-x-0 top-0 h-1/5 bg-gradient-to-b from-n-black/70 to-transparent"
      />
      <div
        class="absolute inset-x-0 bottom-0 h-2/5 bg-gradient-to-t from-n-black/90 via-n-black/70 via-80% to-transparent"
      />
      <img
        :src="globalConfig.logoDark || globalConfig.logo"
        :alt="globalConfig.installationName"
        class="absolute start-10 top-10 z-10 h-8 w-auto max-w-52 object-contain xl:start-14 xl:top-14"
      />
      <div
        class="absolute inset-x-0 bottom-10 px-10 text-start text-white xl:bottom-14 xl:px-14"
      >
        <h1
          class="max-w-lg font-serif text-4xl font-normal leading-tight tracking-tight xl:text-5xl 2xl:text-6xl"
        >
          {{ replaceInstallationName($t('LOGIN.MARKETING.TITLE')) }}
        </h1>
        <p class="mt-4 max-w-md text-base leading-7 xl:text-lg">
          {{ replaceInstallationName($t('LOGIN.MARKETING.SUBTITLE')) }}
        </p>
      </div>
    </aside>

    <section
      class="flex min-h-screen min-w-0 w-full flex-col px-6 py-10 sm:px-12 lg:w-1/2 lg:px-12 xl:px-16"
    >
      <div
        class="mx-auto flex w-full max-w-[30rem] flex-1 flex-col justify-center"
      >
        <div class="mb-10 flex justify-center lg:hidden">
          <img
            :src="globalConfig.logo"
            :alt="globalConfig.installationName"
            class="h-8 w-auto max-w-52 object-contain dark:hidden"
          />
          <img
            :src="globalConfig.logoDark || globalConfig.logo"
            :alt="globalConfig.installationName"
            class="hidden h-8 w-auto max-w-52 object-contain dark:block"
          />
        </div>

        <header class="mb-8 text-center">
          <h2
            class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl"
          >
            {{ replaceInstallationName($t('LOGIN.TITLE')) }}
          </h2>
          <p v-if="showSignupLink" class="mt-3 text-sm text-n-slate-11">
            {{ $t('LOGIN.SIGNUP_PROMPT') }}
            <router-link
              to="/app/auth/signup"
              class="font-medium text-n-brand hover:underline focus-visible:underline"
            >
              {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
            </router-link>
          </p>
          <p v-if="isStaging" class="mt-2 text-xs font-medium text-n-amber-11">
            {{ $t('LOGIN.STAGING_LABEL') }}
          </p>
        </header>

        <section v-if="sessionsLimitReached">
          <SessionLimitOverlay
            :sessions="limitedSessions"
            @revoke="handleSessionRevoke"
            @revoke-all="handleSessionRevokeAll"
            @cancel="handleSessionLimitCancel"
          />
        </section>

        <section v-else-if="mfaRequired">
          <MfaVerification
            :mfa-token="mfaToken"
            @verified="handleMfaVerified"
            @cancel="handleMfaCancel"
          />
        </section>

        <section v-else :class="{ 'animate-wiggle': loginApi.hasErrored }">
          <div v-if="!email">
            <form class="space-y-3" @submit.prevent="submitFormLogin">
              <FormInput
                v-model="credentials.email"
                name="email_address"
                type="email"
                autocomplete="username"
                data-testid="email_input"
                required
                :label="$t('LOGIN.EMAIL.LABEL')"
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                label-sr-only
                outlined
                :has-error="v$.credentials.email.$error"
                @input="v$.credentials.email.$touch"
              />
              <FormInput
                v-model="credentials.password"
                type="password"
                name="password"
                autocomplete="current-password"
                data-testid="password_input"
                required
                :label="$t('LOGIN.PASSWORD.LABEL')"
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                label-sr-only
                outlined
                :has-error="v$.credentials.password.$error"
                @input="v$.credentials.password.$touch"
              />
              <button
                type="submit"
                data-testid="submit_button"
                class="flex h-14 w-full items-center justify-center rounded-full bg-n-slate-12 px-6 text-base font-medium text-n-solid-1 transition-opacity hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-wait"
                :aria-label="$t('LOGIN.SUBMIT')"
                :aria-busy="loginApi.showLoading"
                :disabled="loginApi.showLoading"
              >
                <Spinner
                  v-if="loginApi.showLoading"
                  :size="20"
                  aria-hidden="true"
                />
                <span v-else>{{ $t('LOGIN.SUBMIT') }}</span>
              </button>
            </form>

            <div v-if="showGoogleOAuth || showSamlLogin" class="mt-6 space-y-3">
              <SimpleDivider
                :label="$t('LOGIN.OR')"
                bg="bg-n-solid-1 dark:bg-n-background"
              />
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <router-link
                v-if="showSamlLogin"
                to="/app/login/sso"
                class="flex h-14 w-full items-center justify-center rounded-full border border-n-weak bg-white px-6 text-center text-base font-medium text-n-slate-12 transition-colors hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand dark:border-n-slate-7 dark:text-n-black dark:hover:bg-n-slate-12"
              >
                {{ $t('LOGIN.SAML.LABEL') }}
              </router-link>
            </div>

            <p
              v-if="!globalConfig.disableUserProfileUpdate"
              class="mt-6 text-center"
            >
              <router-link
                to="/app/auth/reset/password"
                class="text-sm text-n-slate-11 hover:text-n-slate-12 hover:underline focus-visible:underline"
              >
                {{ $t('LOGIN.FORGOT_PASSWORD') }}
              </router-link>
            </p>
          </div>
          <div v-else class="flex items-center justify-center text-n-brand">
            <Spinner />
          </div>
        </section>
      </div>
    </section>
  </main>
</template>
