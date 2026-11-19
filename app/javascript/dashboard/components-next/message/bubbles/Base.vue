<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import ReplyPreview from '../ReplyPreview.vue';

import { useMessageContext } from '../provider.js';

import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';
import { CHAT_SKIN } from 'dashboard/helper/chatSkin';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
  overlayMeta: { type: Boolean, default: false },
});

const { variant, orientation, inReplyTo, shouldGroupWithNext } =
  useMessageContext();

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: CHAT_SKIN.bubble.incoming,
  [MESSAGE_VARIANTS.ACTIVITY]:
    'bg-white dark:bg-n-solid-3 shadow-sm px-2 py-0.5 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.TEMPLATE]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'relative [&:has([role=status])_.media-meta]:static [&:has([role=status])_.media-meta]:w-fit [&:has([role=status])_.media-meta]:ms-auto':
          overlayMeta,
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <ReplyPreview v-if="inReplyTo" />
    <slot />
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
        overlayMeta
          ? 'media-meta absolute bottom-2 end-2 rounded-full bg-black/60 px-2 py-0.5 text-white backdrop-blur-sm'
          : variant === MESSAGE_VARIANTS.PRIVATE
            ? 'text-n-amber-12/50'
            : 'text-n-slate-11',
      ]"
      class="mt-1 justify-end"
    />
  </div>
</template>
