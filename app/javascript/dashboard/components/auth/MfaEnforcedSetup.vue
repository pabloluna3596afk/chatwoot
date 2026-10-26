<script setup>
import { ref } from 'vue';
import axios from 'axios';
import { useI18n } from 'vue-i18n';
import {
  parseAPIErrorResponse,
  setAuthCredentials,
} from 'dashboard/store/utils/api';
import MfaSetupWizard from 'dashboard/routes/dashboard/settings/profile/MfaSetupWizard.vue';

const props = defineProps({
  mfaSetupToken: { type: String, required: true },
  provisioningUrl: { type: String, required: true },
  secret: { type: String, required: true },
});
const emit = defineEmits(['verified']);
const { t } = useI18n();
const wizard = ref(null);
const backupCodes = ref([]);
const authResponse = ref(null);

const complete = () => {
  if (!authResponse.value) return;
  setAuthCredentials(authResponse.value);
  emit('verified', authResponse.value.data);
};

const verify = async otpCode => {
  try {
    authResponse.value = await axios.post('/auth/sign_in', {
      mfa_setup_token: props.mfaSetupToken,
      otp_code: otpCode,
    });
    backupCodes.value = authResponse.value.data.backup_codes || [];
    if (!backupCodes.value.length) complete();
  } catch (error) {
    wizard.value?.handleVerificationError(
      parseAPIErrorResponse(error) || t('MFA_SETTINGS.SETUP.INVALID_CODE')
    );
  }
};
</script>

<template>
  <div class="rounded-lg bg-white p-8 shadow-lg dark:bg-n-solid-2">
    <h2 class="mb-2 text-center text-lg font-medium text-n-slate-12">
      {{ $t('MFA_ENFORCED_SETUP.TITLE') }}
    </h2>
    <p class="mb-6 text-center text-sm text-n-slate-11">
      {{ $t('MFA_ENFORCED_SETUP.DESCRIPTION') }}
    </p>
    <MfaSetupWizard
      ref="wizard"
      show-setup
      :mfa-enabled="false"
      :provisioning-uri="provisioningUrl"
      :secret-key="secret"
      :backup-codes="backupCodes"
      @verify="verify"
      @complete="complete"
    />
  </div>
</template>
