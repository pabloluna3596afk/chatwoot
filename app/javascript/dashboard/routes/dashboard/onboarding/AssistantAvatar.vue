<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ src: { type: String, default: '' } });
const { t } = useI18n();
const CAPTAIN_AVATAR_PATH = '/assets/images/dashboard/captain';
</script>

<template>
  <span class="inline-flex shrink-0 overflow-hidden rounded-full">
    <img
      v-if="src"
      :src="src"
      :alt="t('ONBOARDING_ASSISTANT.PHOTO.ALT')"
      class="size-full object-cover"
    />
    <template v-else>
      <img
        :src="`${CAPTAIN_AVATAR_PATH}/avatar-light.svg`"
        :alt="t('ONBOARDING_ASSISTANT.PHOTO.ALT')"
        class="size-full object-cover dark:hidden"
      />
      <img
        :src="`${CAPTAIN_AVATAR_PATH}/avatar-dark.svg`"
        :alt="t('ONBOARDING_ASSISTANT.PHOTO.ALT')"
        class="hidden size-full object-cover dark:block"
      />
    </template>
  </span>
</template>
