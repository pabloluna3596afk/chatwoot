<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import SectionLayout from '../account/components/SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const enabled = ref(false);
const provider = ref('');
const isSaving = ref(false);

watch(
  currentAccount,
  account => {
    enabled.value = account?.settings?.auto_translate === true;
    provider.value = account?.settings?.translation_provider || '';
  },
  { immediate: true, deep: true }
);

const saveSettings = async settings => {
  isSaving.value = true;
  try {
    await updateAccount(settings);
    useAlert(t('CONVERSATION_WORKFLOW.TRANSLATION.SAVED'));
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.TRANSLATION.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const updateProvider = () =>
  saveSettings({ translation_provider: provider.value });

const updateEnabled = () => saveSettings({ auto_translate: enabled.value });
</script>

<template>
  <SectionLayout
    :title="t('CONVERSATION_WORKFLOW.TRANSLATION.TITLE')"
    :description="t('CONVERSATION_WORKFLOW.TRANSLATION.DESCRIPTION')"
    with-border
  >
    <template #headerActions>
      <Switch
        v-model="enabled"
        :disabled="isSaving || (!provider && !enabled)"
        @change="updateEnabled"
      />
    </template>
    <div class="flex flex-col gap-2 max-w-sm">
      <label for="translation-provider" class="text-sm font-medium">
        {{ t('CONVERSATION_WORKFLOW.TRANSLATION.PROVIDER') }}
      </label>
      <select
        id="translation-provider"
        v-model="provider"
        class="!mb-0 text-sm"
        :disabled="isSaving"
        @change="updateProvider"
      >
        <option value="" disabled>
          {{ t('CONVERSATION_WORKFLOW.TRANSLATION.SELECT_PROVIDER') }}
        </option>
        <option value="captain">
          {{ t('CONVERSATION_WORKFLOW.TRANSLATION.CAPTAIN') }}
        </option>
        <option value="google_translate">
          {{ t('CONVERSATION_WORKFLOW.TRANSLATION.GOOGLE_TRANSLATE') }}
        </option>
      </select>
      <p v-if="!provider" class="text-sm text-n-slate-11">
        {{ t('CONVERSATION_WORKFLOW.TRANSLATION.SELECT_PROVIDER') }}
      </p>
    </div>
  </SectionLayout>
</template>
