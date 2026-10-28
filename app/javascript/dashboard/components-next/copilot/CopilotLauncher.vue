<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useCopilotEntryPoints } from 'dashboard/composables/useCopilotEntryPoints';
const { uiSettings, updateUISettings } = useUISettings();
const { showCopilotLauncher } = useCopilotEntryPoints();
const isCopilotPanelOpen = computed(
  () => uiSettings.value.is_copilot_panel_open
);
const toggleSidebar = () => {
  updateUISettings({
    is_copilot_panel_open: !uiSettings.value.is_copilot_panel_open,
  });
};
</script>

<template>
  <div
    v-if="showCopilotLauncher"
    class="fixed ltr:right-4 rtl:left-4 bottom-[calc(env(safe-area-inset-bottom)+1rem)] z-[70]"
  >
    <ButtonGroup
      class="relative rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        id="copilot-launcher-button"
        :aria-label="
          isCopilotPanelOpen
            ? $t('CAPTAIN.COPILOT.MINIMIZE')
            : $t('CAPTAIN.COPILOT.OPEN')
        "
        no-animation
        class="!size-12 !p-0 !rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
        @click="toggleSidebar"
      >
        <template #icon>
          <Transition
            mode="out-in"
            enter-active-class="transition duration-150 ease-out"
            enter-from-class="scale-75 opacity-0"
            enter-to-class="scale-100 opacity-100"
            leave-active-class="transition duration-100 ease-in"
            leave-from-class="scale-100 opacity-100"
            leave-to-class="scale-75 opacity-0"
          >
            <i
              :key="isCopilotPanelOpen ? 'minimize' : 'captain'"
              class="inline-block"
              :class="
                isCopilotPanelOpen ? 'i-lucide-chevron-down' : 'i-woot-captain'
              "
            />
          </Transition>
        </template>
      </Button>
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
