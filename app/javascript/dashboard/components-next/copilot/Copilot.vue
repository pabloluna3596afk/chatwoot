<script setup>
import { nextTick, ref, watch, computed } from 'vue';
import { useTrack } from 'dashboard/composables';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import CopilotInput from './CopilotInput.vue';
import CopilotLoader from './CopilotLoader.vue';
import CopilotAgentMessage from './CopilotAgentMessage.vue';
import CopilotAssistantMessage from './CopilotAssistantMessage.vue';
import CopilotThinkingGroup from './CopilotThinkingGroup.vue';
import ToggleCopilotAssistant from './ToggleCopilotAssistant.vue';
import CopilotEmptyState from './CopilotEmptyState.vue';

const props = defineProps({
  messages: { type: Array, default: () => [] },
  assistants: { type: Array, default: () => [] },
  activeAssistant: { type: Object, default: () => ({}) },
  canSuggestReply: { type: Boolean, default: true },
  onSendMessage: { type: Function, required: true },
  threads: { type: Array, default: () => [] },
  isHistoryOpen: { type: Boolean, default: false },
  isLoadingHistory: { type: Boolean, default: false },
  hasMoreHistory: { type: Boolean, default: false },
  contextId: { type: [Number, String], default: null },
  contextName: { type: String, default: '' },
});
const emit = defineEmits([
  'setAssistant',
  'newChat',
  'selectThread',
  'minimize',
  'close',
  'openHistory',
  'closeHistory',
  'loadMoreHistory',
]);
const sendMessage = async message => {
  const success = await props.onSendMessage(message);
  useTrack(COPILOT_EVENTS.SEND_MESSAGE);
  return success;
};
const chatContainer = ref(null);
const isNearBottom = ref(true);
const newMessageCount = ref(0);
const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value)
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
};
const groupedMessages = computed(() => {
  const result = [];
  let thinkingGroup = [];
  props.messages.forEach(message => {
    if (message.message_type === 'assistant_thinking')
      thinkingGroup.push(message);
    else {
      if (thinkingGroup.length) {
        result.push({
          id: thinkingGroup[0].id,
          message_type: 'thinking_group',
          messages: thinkingGroup,
        });
        thinkingGroup = [];
      }
      result.push(message);
    }
  });
  if (thinkingGroup.length)
    result.push({
      id: thinkingGroup[0].id,
      message_type: 'thinking_group',
      messages: thinkingGroup,
    });
  return result;
});
const isLastMessageFromAssistant = computed(
  () => groupedMessages.value.at(-1)?.message_type === 'assistant'
);
const hasAssistants = computed(() => props.assistants.length > 0);
const hasMessages = computed(() => props.messages.length > 0);
const relativeTime = createdAt => {
  const minutes = Math.round((createdAt * 1000 - Date.now()) / 60000);
  const value = Math.abs(minutes) < 60 ? minutes : Math.round(minutes / 60);
  return new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' }).format(
    value,
    Math.abs(minutes) < 60 ? 'minute' : 'hour'
  );
};
const isTyping = computed(
  () => hasMessages.value && !isLastMessageFromAssistant.value
);
const toggleHistory = () => {
  if (props.isHistoryOpen) emit('closeHistory');
  else emit('openHistory');
};
const handleScroll = () => {
  if (!chatContainer.value) return;
  isNearBottom.value =
    chatContainer.value.scrollHeight -
      chatContainer.value.scrollTop -
      chatContainer.value.clientHeight <
    48;
  if (isNearBottom.value) newMessageCount.value = 0;
};
const jumpToLatest = () => {
  isNearBottom.value = true;
  newMessageCount.value = 0;
  scrollToBottom();
};
watch(
  () => props.messages,
  () => {
    if (isNearBottom.value) scrollToBottom();
    else newMessageCount.value += 1;
  },
  { deep: true }
);
</script>

<template>
  <div
    class="relative flex h-full w-full flex-col text-sm leading-6 tracking-tight"
  >
    <header class="flex flex-col gap-2 border-b border-n-weak px-3 py-2.5">
      <div class="flex items-center gap-2">
        <span
          class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-xl text-n-slate-12"
        >
          <i class="i-woot-captain" />
        </span>
        <div class="min-w-0 flex-1">
          <div class="truncate font-medium text-n-slate-12">
            {{ $t('CAPTAIN.COPILOT.TITLE') }}
          </div>
          <div class="text-xs text-n-slate-10">
            {{
              isTyping
                ? $t('CAPTAIN.COPILOT.TYPING')
                : $t('CAPTAIN.COPILOT.ONLINE')
            }}
          </div>
        </div>
        <button
          type="button"
          class="min-h-11 min-w-11 rounded-md p-2 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="$t('CAPTAIN.COPILOT.NEW_CHAT')"
          :title="$t('CAPTAIN.COPILOT.NEW_CHAT')"
          @click="emit('newChat')"
        >
          <i class="i-lucide-square-pen" />
        </button>
        <button
          type="button"
          class="min-h-11 min-w-11 rounded-md p-2 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="$t('CAPTAIN.COPILOT.HISTORY')"
          :title="$t('CAPTAIN.COPILOT.HISTORY')"
          @click="toggleHistory"
        >
          <i class="i-lucide-history" />
        </button>
        <button
          type="button"
          class="min-h-11 min-w-11 rounded-md p-2 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="$t('CAPTAIN.COPILOT.MINIMIZE')"
          :title="$t('CAPTAIN.COPILOT.MINIMIZE')"
          @click="emit('minimize')"
        >
          <i class="i-lucide-minus" />
        </button>
        <button
          type="button"
          class="min-h-11 min-w-11 rounded-md p-2 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="$t('GENERAL.CLOSE')"
          :title="$t('GENERAL.CLOSE')"
          @click="emit('close')"
        >
          <i class="i-lucide-x" />
        </button>
      </div>
      <div
        v-if="contextId"
        class="truncate rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-11"
      >
        {{
          $t('CAPTAIN.COPILOT.CONTEXT', {
            id: contextId,
            name: contextName || $t('CAPTAIN.COPILOT.UNKNOWN_CONTACT'),
          })
        }}
      </div>
    </header>
    <div
      v-if="isHistoryOpen"
      class="max-h-52 shrink-0 overflow-y-auto border-b border-n-weak p-2"
    >
      <div
        v-if="isLoadingHistory"
        class="p-3 text-center text-xs text-n-slate-10"
      >
        {{ $t('CAPTAIN.COPILOT.LOADING_HISTORY') }}
      </div>
      <button
        v-for="thread in threads"
        :key="thread.id"
        type="button"
        class="block min-h-11 w-full truncate rounded-lg px-3 py-2 text-start text-sm text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('selectThread', thread)"
      >
        {{ thread.title }}
      </button>
      <button
        v-if="hasMoreHistory"
        type="button"
        class="min-h-11 w-full rounded-lg px-3 py-2 text-center text-xs text-n-blue-11 hover:bg-n-alpha-2"
        @click="emit('loadMoreHistory')"
      >
        {{ $t('CAPTAIN.COPILOT.LOAD_MORE') }}
      </button>
      <div
        v-if="!isLoadingHistory && !threads.length"
        class="p-3 text-center text-xs text-n-slate-10"
      >
        {{ $t('CAPTAIN.COPILOT.EMPTY_HISTORY') }}
      </div>
    </div>
    <div
      ref="chatContainer"
      class="relative flex flex-1 items-start overflow-y-auto px-4 py-4"
      @scroll="handleScroll"
    >
      <div v-if="hasMessages" class="flex w-full flex-1 flex-col gap-4">
        <template v-for="(item, index) in groupedMessages" :key="item.id">
          <div v-if="item.message_type === 'user'" class="flex justify-end">
            <div
              class="max-w-[85%] rounded-2xl rounded-br-sm bg-n-brand px-3 py-2 text-white"
            >
              <CopilotAgentMessage :message="item.message" />
              <time
                v-if="item.created_at"
                class="mt-1 block text-end text-[10px] text-white/70"
              >
                {{ relativeTime(item.created_at) }}
              </time>
            </div>
          </div>
          <div
            v-else-if="item.message_type === 'assistant'"
            class="flex items-start gap-2"
          >
            <span
              class="mt-1 flex size-7 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-12"
            >
              <i class="i-woot-captain text-base" />
            </span>
            <div
              class="max-w-[88%] rounded-2xl rounded-bl-sm bg-n-surface-3 px-3 py-2"
            >
              <CopilotAssistantMessage
                :message="item.message"
                :is-last-message="index === groupedMessages.length - 1"
              />
              <time
                v-if="item.created_at"
                class="mt-1 block text-end text-[10px] text-n-slate-10"
              >
                {{ relativeTime(item.created_at) }}
              </time>
            </div>
          </div>
          <CopilotThinkingGroup
            v-else
            :messages="item.messages"
            :default-collapsed="isLastMessageFromAssistant"
          />
        </template>
        <CopilotLoader v-if="isTyping" />
      </div>
      <CopilotEmptyState
        v-else
        :has-assistants="hasAssistants"
        :can-suggest-reply="canSuggestReply"
        @use-suggestion="sendMessage"
      />
    </div>
    <button
      v-if="newMessageCount"
      type="button"
      class="absolute bottom-24 left-1/2 z-10 -translate-x-1/2 rounded-full bg-n-surface-3 px-3 py-1 text-xs text-n-slate-12 shadow"
      @click="jumpToLatest"
    >
      {{ $t('CAPTAIN.COPILOT.NEW_MESSAGES', { count: newMessageCount }) }}
    </button>
    <div class="mx-3 mb-2 mt-px">
      <div class="mb-1 flex w-full items-center justify-between gap-2">
        <ToggleCopilotAssistant
          v-if="assistants.length > 1"
          :assistants="assistants"
          :active-assistant="activeAssistant"
          @set-assistant="emit('setAssistant', $event)"
        />
        <div v-else />
      </div>
      <CopilotInput
        v-if="hasAssistants"
        class="mb-1 w-full"
        :on-send="sendMessage"
      />
    </div>
  </div>
</template>
