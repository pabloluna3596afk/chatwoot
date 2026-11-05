<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount } = useAccount();
const { uiSettings, updateUISettings } = useUISettings();
const isEnabled = ref(false);
const isAccountEnabled = computed(
  () => !!currentAccount.value?.settings?.audio_transcriptions
);

watch(
  uiSettings,
  settings => {
    isEnabled.value = settings?.auto_transcribe_audio === true;
  },
  { immediate: true, deep: true }
);

const toggleAutoTranscription = () => {
  updateUISettings({ auto_transcribe_audio: isEnabled.value });
  useAlert(t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
};
</script>

<template>
  <div class="flex flex-col items-start gap-2">
    <Switch
      v-model="isEnabled"
      :disabled="!isAccountEnabled"
      @change="toggleAutoTranscription"
    />
    <p
      v-if="!isAccountEnabled"
      class="text-xs text-n-slate-11"
      role="note"
    >
      {{ $t('PROFILE_SETTINGS.FORM.AUTO_AUDIO_TRANSCRIPTION.ADMIN_REQUIRED') }}
    </p>
  </div>
</template>
