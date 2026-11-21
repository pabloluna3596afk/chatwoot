<script setup>
import { computed } from 'vue';
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

const props = defineProps({
  message: { type: Object, default: null },
  composer: { type: Boolean, default: false },
});
const context = props.composer ? null : useMessageContext();
const channelType = computed(() => context?.channelType.value || '');
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
    image: 'PHOTO',
    video: 'VIDEO',
    ig_reel: 'VIDEO',
    file: 'FILE',
    audio: 'AUDIO',
    location: 'LOCATION',
    contact: 'CONTACT',
  };
  const key =
    attachment.value.fileType === 'file' &&
    attachmentExtension(attachment.value) === 'pdf'
      ? 'PDF'
      : types[attachment.value.fileType];
  return key
    ? t(`CONVERSATION.REPLY_PREVIEW.${key}`)
    : message.value?.sender?.name || '';
});
const { isLoaded, hasError, isExpired, onLoad, onError } = useMediaState(
  attachment,
  channelType,
  thumbnail
);
const heading = computed(() =>
  isExpired.value
    ? t('CONVERSATION.REPLY_PREVIEW.UNAVAILABLE', { type: type.value })
    : type.value
);
const text = computed(() => {
  if (message.value?.content)
    return new MessageFormatter(message.value.content).formattedMessage;
  return (
    middleEllipsis(attachmentName(attachment.value)) ||
    t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND')
  );
});
const scrollToMessage = () =>
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: message.value.id });
</script>

<template>
  <button
    type="button"
    class="flex items-center gap-2 p-1.5 -mx-1 mb-2 rounded-lg bg-n-alpha-black1 border-s-[3px] border-n-brand cursor-pointer text-start w-full min-w-0"
    :class="
      composer
        ? '!mx-0 !mb-0 !p-2 !bg-transparent'
        : attachment.fileType
          ? '!mx-0 !p-2 !gap-2.5 !bg-n-alpha-1 ring-1 ring-n-weak hover:!bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand'
          : ''
    "
    @click="scrollToMessage"
  >
    <span
      v-if="hasThumbnail && !hasError"
      class="relative size-9 shrink-0 rounded-md overflow-hidden"
    >
      <span
        v-if="!isLoaded"
        class="absolute inset-0 animate-pulse motion-reduce:animate-none bg-n-alpha-2"
      />
      <img
        :src="thumbnail"
        :alt="type"
        class="size-9 object-cover"
        loading="lazy"
        decoding="async"
        @load="onLoad"
        @error="onError"
      />
    </span>
    <FileIcon
      v-else-if="attachment.fileType === 'file' || hasError"
      :file-type="attachmentExtension(attachment)"
      class="size-8 shrink-0 text-n-slate-12"
    />
    <Icon
      v-else-if="attachment.fileType === 'audio'"
      icon="i-lucide-mic"
      class="size-8 shrink-0 text-n-slate-12"
    />
    <span
      class="min-w-0 flex flex-col"
      :class="attachment.fileType ? 'gap-0.5' : ''"
    >
      <span
        v-if="heading"
        class="text-xs font-semibold text-n-brand line-clamp-1 break-all"
        >{{ heading }}</span
      >
      <span
        v-dompurify-html="text"
        :class="
          composer || attachment.fileType
            ? 'text-xs leading-4 text-n-slate-12 line-clamp-2 break-all'
            : 'text-xs text-n-slate-11 truncate'
        "
      />
    </span>
  </button>
</template>
