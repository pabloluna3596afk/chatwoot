<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from '../../account/components/SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const isEnabled = ref(false);
watch(
  currentAccount,
  account => {
    isEnabled.value = !!account?.settings?.enforce_mfa;
  },
  { deep: true, immediate: true }
);

const updateEnforcement = async () => {
  const previous = !isEnabled.value;
  try {
    await updateAccount({ enforce_mfa: isEnabled.value });
    useAlert(t('SECURITY_SETTINGS.MFA.SUCCESS'));
  } catch {
    isEnabled.value = previous;
    useAlert(t('SECURITY_SETTINGS.MFA.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('SECURITY_SETTINGS.MFA.TITLE')"
    :description="t('SECURITY_SETTINGS.MFA.DESCRIPTION')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="updateEnforcement" />
      </div>
    </template>
  </SectionLayout>
</template>
