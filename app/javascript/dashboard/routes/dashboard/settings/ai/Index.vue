<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import AudioTranscription from '../account/components/AudioTranscription.vue';

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const canManageAudioTranscription = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CAPTAIN)
);
</script>

<template>
  <div class="flex flex-col w-full max-w-2xl ltr:mr-auto">
    <h1 class="min-w-0 break-words text-heading-1 text-n-slate-12">
      {{ t('SIDEBAR.AI') }}
    </h1>
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <AudioTranscription v-if="canManageAudioTranscription" />
    </div>
  </div>
</template>
