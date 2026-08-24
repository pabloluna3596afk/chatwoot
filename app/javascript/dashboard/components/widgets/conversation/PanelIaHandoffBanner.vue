<script setup>
import { computed, toRef } from 'vue';

import { usePanelIaState } from 'dashboard/composables/usePanelIaState';

import Banner from 'dashboard/components/ui/Banner.vue';

const props = defineProps({
  chat: {
    type: Object,
    required: true,
  },
});

const { state, isBotHandled } = usePanelIaState(toRef(props, 'chat'));

const showBanner = computed(
  () => isBotHandled.value && state.value === 'solicita_ayuda'
);
</script>

<template>
  <div
    v-if="showBanner"
    class="relative z-20 shrink-0 border-b border-n-weak bg-n-surface-1"
  >
    <Banner
      color-scheme="secondary"
      class="!rounded-none !shadow-none !border-x-0 !border-t-0"
      :banner-message="$t('CONVERSATION.PANEL_IA_HANDOFF_BANNER')"
    />
  </div>
</template>
