<script setup>
import { computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useToggle } from '@vueuse/core';
import MultiselectDropdownItems from 'shared/components/ui/MultiselectDropdownItems.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { useConversationAssignee } from 'dashboard/composables/useConversationAssignee';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

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

const [showMenu, toggleMenu] = useToggle(false);

const fetchAssignableAgents = () => {
  const inboxId = store.getters.getSelectedChat?.inbox_id;
  if (inboxId) {
    store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
  }
};

onMounted(fetchAssignableAgents);

watch(
  () => store.getters.getSelectedChat?.inbox_id,
  () => fetchAssignableAgents()
);

const displayName = computed(
  () => assignedAgent.value?.name || t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')
);

const closeMenu = () => toggleMenu(false);

const onTriggerClick = () => {
  if (isAssigning.value) return;
  toggleMenu();
};

const onSelectAgent = agent => {
  onClickAssignAgent(agent);
  closeMenu();
};

const onClickSelfAssign = () => {
  onSelfAssign();
  closeMenu();
};
</script>

<template>
  <OnClickOutside @trigger="closeMenu">
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
        <Avatar
          v-if="assignedAgent"
          :name="assignedAgent.name"
          :src="assignedAgent.thumbnail"
          :status="assignedAgent.availability_status"
          :size="18"
          hide-offline-status
          rounded-full
          class="shrink-0"
        />
        <span
          class="min-w-0 text-sm text-n-slate-12 truncate"
          :title="displayName"
        >
          {{ displayName }}
        </span>
      </button>
      <div
        v-if="showMenu"
        class="box-border border rounded-lg bg-n-alpha-3 backdrop-blur-[100px] absolute shadow-lg border-n-strong dark:border-n-strong p-2 z-[9999] top-9 ltr:right-0 rtl:left-0 min-w-[16rem] w-max"
      >
        <div class="flex items-center justify-between mb-1">
          <h4
            class="m-0 overflow-hidden text-sm text-n-slate-11 whitespace-nowrap text-ellipsis"
          >
            {{ $t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT') }}
          </h4>
          <NextButton
            variant="ghost"
            color="slate"
            size="xs"
            icon="i-lucide-x"
            @click="closeMenu"
          />
        </div>
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
        <MultiselectDropdownItems
          :options="agentsList"
          :selected-items="assignedAgent ? [assignedAgent] : []"
          has-thumbnail
          :input-placeholder="
            $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
          "
          :no-search-result="
            $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
          "
          @select="onSelectAgent"
        />
      </div>
    </div>
  </OnClickOutside>
</template>
