<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import MessageFormatter from 'shared/helpers/MessageFormatter';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import FileIcon from 'next/icon/FileIcon.vue';
import Icon from 'next/icon/Icon.vue';
import {
  attachmentName,
  attachmentExtension,
  middleEllipsis,
} from './media/attachment';
import { useMediaState } from './media/useMediaState';
import {
  activeJumpMessageId,
  unavailableJumpTargets,
  jumpTargetKey,
} from './useJumpToMessage';
import { MESSAGE_TYPES } from './constants';

const props = defineProps({
  message: { type: Object, default: null },
  composer: { type: Boolean, default: false },
  currentUserId: { type: Number, default: null },
  conversationId: { type: Number, default: null },
});
const context = props.composer ? null : useMessageContext();
const channelType = computed(() => context?.channelType.value || '');
const currentUserIdRef = context?.currentUserId || ref(props.currentUserId);
const { t } = useI18n();
const message = computed(() =>
  useCamelCase(props.message || context?.inReplyTo.value, { deep: true })
);
const attachment = computed(() => message.value?.attachments?.[0] || {});
const hasThumbnail = computed(() =>
  ['image', 'video', 'ig_reel'].includes(attachment.value.fileType)
);
const thumbnail = computed(
  () => attachment.value.thumbUrl || attachment.value.dataUrl
);
const type = computed(() => {
  const types = {
    image: t('CONVERSATION.REPLY_PREVIEW.PHOTO'),
    video: t('CONVERSATION.REPLY_PREVIEW.VIDEO'),
    ig_reel: t('CONVERSATION.REPLY_PREVIEW.VIDEO'),
    file: t('CONVERSATION.REPLY_PREVIEW.FILE'),
    audio: t('CONVERSATION.REPLY_PREVIEW.AUDIO'),
    location: t('CONVERSATION.REPLY_PREVIEW.LOCATION'),
    contact: t('CONVERSATION.REPLY_PREVIEW.CONTACT'),
  };
  const key =
    attachment.value.fileType === 'file' &&
    attachmentExtension(attachment.value) === 'pdf'
      ? t('CONVERSATION.REPLY_PREVIEW.PDF')
      : types[attachment.value.fileType];
  return key || '';
});
const { isLoaded, hasError, isExpired, onLoad, onError } = useMediaState(
  attachment,
  channelType,
  thumbnail
);
const senderId = computed(
  () => message.value?.senderId ?? message.value?.sender?.id
);
const isAgentMessage = computed(() =>
  [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE].includes(
    message.value?.messageType
  )
);
const isPrivate = computed(() => Boolean(message.value?.private));
const contentExcerpt = computed(() => {
  if (!message.value?.content) return '';
  const doc = new DOMParser().parseFromString(
    new MessageFormatter(message.value.content).formattedMessage,
    'text/html'
  );
  doc.querySelectorAll('br, p, li, div, pre').forEach(node => node.append(' '));
  return (doc.body.textContent || '').replace(/\s+/g, ' ').trim();
});
const author = computed(() => {
  if (isPrivate.value) return t('CONVERSATION.REPLYBOX.PRIVATE_NOTE');
  if (
    isAgentMessage.value &&
    currentUserIdRef.value != null &&
    senderId.value != null &&
    Number(senderId.value) ===
      Number(currentUserIdRef.value?.value ?? currentUserIdRef.value)
  )
    return t('CONVERSATION.REPLY_PREVIEW.YOU');
  return (
    message.value?.sender?.name ||
    message.value?.senderName ||
    t('CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR')
  );
});
const tone = computed(() => {
  if (isPrivate.value) return 'amber';
  if (isAgentMessage.value) return 'teal';
  return 'blue';
});
const excerpt = computed(() => {
  if (isExpired.value || (hasThumbnail.value && hasError.value)) {
    return t('CONVERSATION.REPLY_PREVIEW.UNAVAILABLE', {
      type: type.value || t('CONVERSATION.REPLY_PREVIEW.PHOTO'),
    });
  }
  if (attachment.value.fileType) {
    const filename = ['image', 'video', 'ig_reel'].includes(
      attachment.value.fileType
    )
      ? ''
      : middleEllipsis(attachmentName(attachment.value));
    return [type.value, filename, contentExcerpt.value]
      .filter(Boolean)
      .join(' ')
      .slice(0, 240);
  }
  if (!message.value?.content) return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
  return contentExcerpt.value.slice(0, 240);
});
const isCrossConversation = computed(
  () =>
    message.value?.conversationId &&
    (props.conversationId || context?.conversationId?.value) &&
    Number(message.value.conversationId) !==
      Number(props.conversationId || context.conversationId.value)
);
const canJump = computed(
  () =>
    Boolean(message.value?.id) &&
    !message.value?.contentAttributes?.deleted &&
    !unavailableJumpTargets.value.has(
      jumpTargetKey(
        props.conversationId ||
          context?.conversationId?.value ||
          message.value?.conversationId,
        message.value?.id
      )
    ) &&
    !isCrossConversation.value
);
const isLoading = computed(
  () => Number(activeJumpMessageId.value) === Number(message.value?.id)
);
const barToneClasses = computed(() => ({
  'bg-n-blue-9/70': tone.value === 'blue',
  'bg-n-teal-9/70': tone.value === 'teal',
  'bg-n-amber-9/70': tone.value === 'amber',
}));
const authorToneClasses = computed(() => ({
  'text-n-blue-11': tone.value === 'blue',
  'text-n-teal-11': tone.value === 'teal',
  'text-n-amber-11': tone.value === 'amber',
}));
const scrollToMessage = () => {
  if (!canJump.value) return;
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: message.value.id,
    source: 'reply',
    conversationId: message.value.conversationId,
  });
};
const replyExcerptClass = 'line-clamp-1 sm:line-clamp-2';
const containerClass = computed(() =>
  props.composer
    ? 'rounded-none bg-transparent flex-1'
    : 'rounded-lg bg-n-alpha-black1'
);
</script>

<template>
  <button
    type="button"
    class="box-border flex w-full min-w-0 items-stretch overflow-hidden p-0 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand focus-visible:outline-offset-1"
    :class="[
      containerClass,
      composer ? 'flex-1' : 'mb-1.5',
      canJump ? 'cursor-pointer hover:bg-n-alpha-black2' : 'cursor-default',
    ]"
    :aria-label="
      composer
        ? t('CONVERSATION.REPLY_PREVIEW.REPLYING_TO_AUTHOR', { author })
        : canJump
          ? t('CONVERSATION.REPLY_PREVIEW.GO_TO_MESSAGE', { author })
          : undefined
    "
    :disabled="!canJump"
    :aria-busy="isLoading"
    @click="scrollToMessage"
  >
    <span
      class="w-[0.1875rem] shrink-0"
      :class="barToneClasses"
      aria-hidden="true"
    />
    <span class="flex min-w-0 flex-1 flex-col gap-0.5 py-1 ps-2 pe-2">
      <span
        class="line-clamp-1 break-all text-xs font-semibold"
        :class="authorToneClasses"
      >
        {{ author || message?.sender?.name }}
      </span>
      <span
        dir="auto"
        class="min-w-0 text-xs leading-4 text-n-slate-11"
        :class="replyExcerptClass"
      >
        <Icon
          v-if="isLoading"
          icon="i-lucide-loader-circle"
          class="me-1 inline size-3 animate-spin motion-reduce:animate-none"
        />
        <Icon
          v-else-if="hasThumbnail"
          :icon="
            attachment.fileType === 'image'
              ? 'i-lucide-image'
              : 'i-lucide-video'
          "
          class="me-1 inline size-3.5"
        />
        <FileIcon
          v-else-if="attachment.fileType === 'file'"
          :file-type="attachmentExtension(attachment)"
          class="me-1 inline size-3.5"
        />
        <Icon
          v-else-if="attachment.fileType === 'audio'"
          icon="i-lucide-mic"
          class="me-1 inline size-3.5"
        />
        <Icon
          v-else-if="attachment.fileType === 'location'"
          icon="i-lucide-map-pin"
          class="me-1 inline size-3.5"
        />
        <Icon
          v-else-if="attachment.fileType === 'contact'"
          icon="i-lucide-user-round"
          class="me-1 inline size-3.5"
        />
        {{ excerpt }}
      </span>
    </span>
    <span
      v-if="hasThumbnail && !hasError && thumbnail"
      class="relative size-10 shrink-0 overflow-hidden"
    >
      <span
        v-if="!isLoaded"
        class="absolute inset-0 animate-pulse bg-n-alpha-2 motion-reduce:animate-none"
      />
      <img
        :src="thumbnail"
        :alt="type"
        class="size-full object-cover"
        loading="lazy"
        decoding="async"
        @load="onLoad"
        @error="onError"
      />
      <span
        v-if="['video', 'ig_reel'].includes(attachment.fileType)"
        class="absolute inset-0 grid place-items-center bg-n-alpha-black2"
        aria-hidden="true"
      >
        <Icon
          icon="i-lucide-play"
          class="size-3 text-n-slate-1 dark:text-n-slate-12"
        />
      </span>
    </span>
  </button>
</template>
