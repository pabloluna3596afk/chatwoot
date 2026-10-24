<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const emit = defineEmits(['close', 'createAssistant']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const assistants = useMapGetter('captainAssistants/getRecords');

const currentAssistantId = computed(() => route.params.assistantId);

const isAssistantActive = assistant => {
  return assistant.id === Number(currentAssistantId.value);
};

const menuItems = computed(() =>
  assistants.value.map(assistant => ({
    label: assistant.name,
    title: assistant.name,
    assistant,
    isSelected: isAssistantActive(assistant),
    thumbnail: { name: assistant.name, src: assistant.avatar_url },
  }))
);

const fetchDataForRoute = async (routeName, assistantId) => {
  const dataFetchMap = {
    captain_assistants_documents_index: async () => {
      await store.dispatch('captainDocuments/get', { assistantId });
    },
    captain_assistants_scenarios_index: async () => {
      await store.dispatch('captainScenarios/get', { assistantId });
    },
    captain_assistants_playground_index: () => {
      // Playground doesn't need pre-fetching, it loads on interaction
    },
    captain_assistants_inboxes_index: async () => {
      await store.dispatch('captainInboxes/get', { assistantId });
    },
    captain_tools_index: async () => {
      await store.dispatch('captainCustomTools/get', { page: 1 });
    },
    captain_assistants_settings_index: async () => {
      await store.dispatch('captainAssistants/show', assistantId);
    },
  };

  const fetchFn = dataFetchMap[routeName];
  if (fetchFn) {
    await fetchFn();
  }
};

const handleAssistantChange = async assistant => {
  if (isAssistantActive(assistant)) return;

  const currentRouteName = route.name;
  const targetRouteName =
    currentRouteName || 'captain_assistants_overview_index';

  await fetchDataForRoute(targetRouteName, assistant.id);

  await router.push({
    name: targetRouteName,
    params: {
      accountId: route.params.accountId,
      assistantId: assistant.id,
    },
  });

  emit('close');
};

const openCreateAssistantDialog = () => {
  emit('createAssistant');
  emit('close');
};
</script>

<template>
  <MenuPopover
    :menu-items="menuItems"
    :label="t('CAPTAIN.ASSISTANT_SWITCHER.SWITCH_ASSISTANT')"
    show-search
    align="start"
    panel-class="w-[27.5rem] max-w-[calc(100vw-2rem)] max-sm:[&_button]:min-h-11"
    @action="handleAssistantChange($event.assistant)"
  >
    <template #trigger="{ open, toggle }">
      <slot name="trigger" :open="open" :toggle="toggle">
        <Button
          icon="i-lucide-chevron-down"
          :aria-label="t('CAPTAIN.ASSISTANT_SWITCHER.SWITCH_ASSISTANT')"
          :aria-expanded="open"
          aria-haspopup="dialog"
          color="slate"
          variant="ghost"
          class="min-h-11 min-w-11 sm:min-h-0 sm:min-w-0"
          @click="toggle"
        />
      </slot>
    </template>
    <template #footer="{ close }">
      <div class="p-3 border-t border-n-weak">
        <Button
          :label="t('CAPTAIN.ASSISTANT_SWITCHER.NEW_ASSISTANT')"
          color="slate"
          icon="i-lucide-plus"
          class="w-full min-h-11 sm:min-h-0"
          @click="
            close(false);
            openCreateAssistantDialog();
          "
        />
      </div>
    </template>
  </MenuPopover>
</template>
