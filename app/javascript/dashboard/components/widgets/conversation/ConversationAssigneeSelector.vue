<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  getAssigneeSelectionKey,
  isSameAssignee,
} from 'dashboard/helper/assigneeHelper';
import { useConversationAssignee } from 'dashboard/composables/useConversationAssignee';
import { useCaptainState } from 'dashboard/composables/useCaptainState';
import { useI18n } from 'vue-i18n';

defineProps({
  showSelfAssignButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();

const {
  agentsList,
  assignedAgent,
  showSelfAssign,
  isAssigning,
  onClickAssignAgent,
  onSelfAssign,
} = useConversationAssignee();

const showMenu = ref(false);

// While Captain answers, the chip shows the assistant's own photo inside the state ring (as the conversation card does).
const {
  showAssistantAvatar,
  assistant: captainAssistant,
  ringClass: captainRingClass,
} = useCaptainState(computed(() => store.getters.getSelectedChat));
const chipThumbnail = computed(() =>
  showAssistantAvatar.value
    ? captainAssistant.value.thumbnail || assignedAgent.value?.thumbnail
    : assignedAgent.value?.thumbnail
);

const fetchAssignableAgents = () => {
  const inboxId = store.getters.getSelectedChat?.inbox_id;
  if (inboxId) {
    store.dispatch('inboxAssignableAgents/fetch', {
      inboxIds: [inboxId],
      includeAIAssignees: true,
    });
  }
};

onMounted(fetchAssignableAgents);

watch(
  () => store.getters.getSelectedChat?.inbox_id,
  () => fetchAssignableAgents()
);

const menuItems = computed(() =>
  agentsList.value.map(agent => ({
    label: agent.name,
    value: getAssigneeSelectionKey(agent),
    action: 'assign',
    agent,
    isSelected:
      !!assignedAgent.value && isSameAssignee(assignedAgent.value, agent),
    disabled: isAssigning.value,
  }))
);
const displayName = computed(
  () => assignedAgent.value?.name || t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')
);

const closeMenu = () => {
  showMenu.value = false;
};

const onTriggerClick = () => {
  if (isAssigning.value) return;
  showMenu.value = !showMenu.value;
};

const onSelectAgent = item => {
  onClickAssignAgent(item.agent);
  closeMenu();
};

const onClickSelfAssign = () => {
  onSelfAssign();
  closeMenu();
};
</script>

<template>
  <MenuPopover
    v-model:open="showMenu"
    :menu-items="menuItems"
    show-search
    :search-placeholder="
      t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
    "
    :label="t('CONVERSATION.HEADER.ASSIGNEE')"
    panel-class="w-64 max-w-[calc(100vw-2rem)]"
    @action="onSelectAgent"
  >
    <template #trigger>
      <div
        v-tooltip="t('CONVERSATION.HEADER.ASSIGNEE')"
        class="relative flex items-center h-8 min-w-0 max-w-[10rem] rounded-lg outline outline-1 outline-n-weak bg-n-background shrink-0"
      >
        <button
          type="button"
          class="flex flex-1 min-w-0 items-center gap-1.5 h-full px-2.5 text-left border-0 bg-transparent hover:bg-n-alpha-2 rounded-lg"
          :disabled="isAssigning"
          @click="onTriggerClick"
        >
          <span
            v-if="assignedAgent"
            class="inline-flex shrink-0 rounded-full"
            :class="showAssistantAvatar ? ['ring-2', captainRingClass] : ''"
            data-testid="assignee-chip-avatar"
          >
            <Avatar
              :name="assignedAgent.name"
              :src="chipThumbnail"
              :status="assignedAgent.availability_status"
              :size="18"
              hide-offline-status
              rounded-full
            />
          </span>
          <span
            class="min-w-0 text-sm text-n-slate-12 truncate"
            :title="displayName"
          >
            {{ displayName }}
          </span>
        </button>
      </div>
    </template>
    <template #thumbnail="{ item }">
      <Avatar
        v-if="!item.agent.icon || item.agent.assignee_type === 'AgentBot'"
        :name="item.agent.name"
        :src="item.agent.thumbnail"
        :status="item.agent.availability_status"
        :icon-name="
          item.agent.assignee_type === 'AgentBot' ? 'i-lucide-bot' : undefined
        "
        :size="24"
        hide-offline-status
        rounded-full
      >
        <template
          v-if="item.agent.assignee_type === 'AgentBot' && item.agent.thumbnail"
          #badge
        >
          <div
            class="absolute z-20 flex items-center justify-center rounded-full outline outline-1 outline-n-weak bg-n-solid-1 -bottom-0.5 ltr:-right-0.5 rtl:-left-0.5 size-3.5"
          >
            <Icon icon="i-lucide-bot" class="text-n-slate-11 size-2.5" />
          </div>
        </template>
      </Avatar>
      <Icon v-else :icon="item.agent.icon" class="size-5 text-n-slate-11" />
    </template>
    <template v-if="showSelfAssignButton && showSelfAssign" #footer>
      <button
        v-if="showSelfAssignButton && showSelfAssign"
        type="button"
        class="flex w-full items-center gap-2 mb-1 px-2 py-1.5 rounded-md text-sm font-medium text-n-blue-11 hover:bg-n-alpha-2 border-0 bg-transparent cursor-pointer text-start disabled:opacity-50"
        :disabled="isAssigning"
        @click="onClickSelfAssign"
      >
        <span class="i-lucide-user-round-plus size-4 shrink-0" />
        {{ t('CONVERSATION_SIDEBAR.SELF_ASSIGN') }}
      </button>
    </template>
  </MenuPopover>
</template>
