<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';
import { hasCaptainDetails } from '../helpers/captainDecision';
import { useMessageSource } from 'dashboard/composables/useMessageSource';
import ReplyPreview from '../ReplyPreview.vue';

import { useMessageContext } from '../provider.js';

import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';
import { CHAT_SKIN } from 'dashboard/helper/chatSkin';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
  captainDetailsAtStart: { type: Boolean, default: false },
});

const {
  id,
  sender,
  senderType,
  contentAttributes,
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
} = useMessageContext();
const { icon: sourceIcon } = useMessageSource(contentAttributes);
const showCaptain = computed(() =>
  hasCaptainDetails({
    sender: sender?.value,
    senderType: senderType?.value,
    contentAttributes: contentAttributes?.value,
  })
);

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: CHAT_SKIN.bubble.incoming,
  [MESSAGE_VARIANTS.ACTIVITY]:
    'bg-n-solid-2 shadow-sm px-3 py-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.TEMPLATE]: CHAT_SKIN.bubble.outgoing,
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-[0.875rem] ltr:rounded-bl-none rtl:rounded-br-none',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-[0.875rem] ltr:rounded-br-none rtl:rounded-bl-none',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value], 'shadow-sm');
  } else {
    classToApply.push('rounded-full');
  }

  return classToApply;
});

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    (!shouldGroupWithNext.value || sourceIcon.value || showCaptain.value) &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);
const metaClass = computed(() => [
  'mt-1 justify-end text-n-slate-11',
  variant.value === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
]);
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg':
          variant !== MESSAGE_VARIANTS.EMAIL &&
          variant !== MESSAGE_VARIANTS.ACTIVITY,
      },
    ]"
  >
    <ReplyPreview v-if="inReplyTo" />
    <slot />
    <template v-if="shouldShowMeta">
      <CaptainGenerationDetails
        v-if="showCaptain && !props.captainDetailsAtStart"
        :message-id="id"
      >
        <template #meta="{ trigger }">
          <MessageMeta
            :show-timestamp="!shouldGroupWithNext"
            :class="metaClass"
          >
            <template #captain><component :is="trigger" /></template>
          </MessageMeta>
        </template>
      </CaptainGenerationDetails>
      <MessageMeta
        v-else
        :show-timestamp="!shouldGroupWithNext"
        :class="metaClass"
      />
    </template>
  </div>
</template>
