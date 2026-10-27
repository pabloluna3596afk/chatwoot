<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
const { uiSettings, updateUISettings } = useUISettings();

const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const showCopilotLauncher = computed(() => {
  const isCaptainEnabled = isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN
  );
  return isCaptainEnabled && !uiSettings.value.is_copilot_panel_open;
});
const toggleSidebar = () => {
  updateUISettings({
    is_copilot_panel_open: !uiSettings.value.is_copilot_panel_open,
    is_contact_sidebar_open: false,
  });
};
</script>

<template>
  <div
    v-if="showCopilotLauncher"
    class="fixed bottom-[calc(env(safe-area-inset-bottom)+1rem)] ltr:right-4 rtl:left-4 z-50"
  >
    <ButtonGroup
      class="relative rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        id="copilot-launcher-button"
        icon="i-woot-captain"
        :aria-label="$t('CAPTAIN.COPILOT.OPEN')"
        no-animation
        class="!size-12 !p-0 !rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
        @click="toggleSidebar"
      />
      <span
        v-if="uiSettings.copilot_unread_count"
        class="absolute -top-1 -right-1 flex min-w-4 h-4 items-center justify-center rounded-full bg-n-ruby-9 px-1 text-[10px] font-medium text-white"
        aria-live="polite"
      >
        {{
          uiSettings.copilot_unread_count > 9
            ? $t('CAPTAIN.COPILOT.MANY_UNREAD')
            : uiSettings.copilot_unread_count
        }}
      </span>
    </ButtonGroup>
  </div>
  <template v-else />
</template>
