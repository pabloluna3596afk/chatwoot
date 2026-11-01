<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useAlert, useTrack } from 'dashboard/composables';

import { BUS_EVENTS } from 'shared/constants/busEvents';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isLastMessage: {
    type: Boolean,
    default: false,
  },
  message: {
    type: Object,
    required: true,
  },
  timeLabel: {
    type: String,
    default: '',
  },
});
const emit = defineEmits(['retry']);
const { t } = useI18n();
const hasEmptyMessageContent = computed(() => !props.message?.content);
const copied = ref(false);
let copiedTimeout;

const showUseButton = computed(() => {
  return (
    !hasEmptyMessageContent.value &&
    props.message.reply_suggestion &&
    props.isLastMessage
  );
});
const copyResponse = async () => {
  try {
    await copyTextToClipboard(props.message.content);
    copied.value = true;
    window.clearTimeout(copiedTimeout);
    copiedTimeout = window.setTimeout(() => {
      copied.value = false;
    }, 1500);
    useAlert(t('CAPTAIN.COPILOT.COPIED'));
  } catch {
    useAlert(t('CAPTAIN.COPILOT.COPY_ERROR'));
  }
};

onUnmounted(() => window.clearTimeout(copiedTimeout));

const messageContent = computed(() => {
  const formatter = new MessageFormatter(props.message.content);
  return formatter.formattedMessage;
});

const useCopilotResponse = () => {
  // Always insert through the rich editor so the markdown is parsed into proper
  // paragraph/hard_break nodes. The plain-text path inserts the reply as a single
  // text node with raw newlines, which the editor collapses into one paragraph as
  // soon as the agent edits the draft.
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, props.message?.content);
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
};
</script>

<template>
  <div
    class="group flex flex-col gap-1"
    :class="message.error ? 'text-n-ruby-11' : 'text-n-slate-12'"
  >
    <div class="font-medium">{{ $t('CAPTAIN.COPILOT.COPILOT_LABEL') }}</div>
    <span v-if="hasEmptyMessageContent" class="text-n-ruby-11">
      {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
    </span>
    <div
      v-else
      v-dompurify-html="messageContent"
      class="prose-sm max-w-none break-words [&_a]:text-n-blue-11 [&_a]:underline [&_code]:rounded [&_code]:bg-n-alpha-2 [&_code]:px-1 [&_pre]:overflow-x-auto [&_pre]:rounded-lg [&_pre]:bg-n-surface-1 [&_pre]:p-3 [&_table]:block [&_table]:max-w-full [&_table]:overflow-x-auto [&_th]:border [&_td]:border [&_th]:border-n-weak [&_td]:border-n-weak [&_th]:px-2 [&_td]:px-2"
    />
    <Button
      v-if="message.error && isLastMessage"
      :label="$t('CAPTAIN.COPILOT.RETRY')"
      intent="secondary"
      size="sm"
      @click="emit('retry')"
    />
    <div
      v-if="!hasEmptyMessageContent || timeLabel"
      class="mt-1 flex min-h-8 flex-row items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:pointer-events-auto group-hover:opacity-100 group-focus-within:pointer-events-auto group-focus-within:opacity-100 [@media(hover:none)]:pointer-events-auto [@media(hover:none)]:opacity-100 motion-reduce:transition-none"
    >
      <Button
        v-if="!hasEmptyMessageContent"
        :aria-label="$t('CAPTAIN.COPILOT.COPY_RESPONSE')"
        :title="$t('CAPTAIN.COPILOT.COPY_RESPONSE')"
        :icon="copied ? 'i-lucide-check' : 'i-lucide-copy'"
        intent="tertiary"
        size="sm"
        @click="copyResponse"
      />
      <Button
        v-if="showUseButton"
        :aria-label="$t('CAPTAIN.COPILOT.USE_RESPONSE')"
        :title="$t('CAPTAIN.COPILOT.USE_RESPONSE')"
        icon="i-lucide-reply"
        intent="tertiary"
        size="sm"
        @click="useCopilotResponse"
      />
      <time v-if="timeLabel" class="px-1 text-[10px] text-n-slate-10">
        {{ timeLabel }}
      </time>
      <span role="status" aria-live="polite" class="sr-only">
        {{ copied ? $t('CAPTAIN.COPILOT.COPIED') : '' }}
      </span>
    </div>
  </div>
</template>
