<script setup>
import { onMounted, onBeforeUnmount, computed, ref, toRefs } from 'vue';
import { provideMessageContext } from './provider.js';
import { useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { isMessageRenderable } from './helpers/messageVisibility';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { LocalStorage } from 'shared/helpers/localStorage';
import { ACCOUNT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  MESSAGE_TYPES,
  ATTACHMENT_TYPES,
  MESSAGE_VARIANTS,
  SENDER_TYPES,
  ORIENTATION,
  MESSAGE_STATUS,
  CONTENT_TYPES,
} from './constants';

import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';
import { useSwipeToReply, REPLY_INTERACTIVE_SELECTOR } from './useSwipeToReply';

import TextBubble from './bubbles/Text/Index.vue';
import CaptainHandoffBubble from './bubbles/CaptainHandoff.vue';
import ActivityBubble from './bubbles/Activity.vue';
import ImageBubble from './bubbles/Image.vue';
import FileBubble from './bubbles/File.vue';
import AudioBubble from './bubbles/Audio.vue';
import VideoBubble from './bubbles/Video.vue';
import EmbedBubble from './bubbles/Embed.vue';
import FallbackBubble from './bubbles/Fallback.vue';
import InstagramStoryBubble from './bubbles/InstagramStory.vue';
import EmailBubble from './bubbles/Email/Index.vue';
import UnsupportedBubble from './bubbles/Unsupported.vue';
import ContactBubble from './bubbles/Contact.vue';
import DyteBubble from './bubbles/Dyte.vue';
import LocationBubble from './bubbles/Location.vue';
import CSATBubble from './bubbles/CSAT.vue';
import FormBubble from './bubbles/Form.vue';
import VoiceCallBubble from './bubbles/VoiceCall.vue';
import WhatsappFlowSentBubble from './bubbles/WhatsappFlowSent.vue';
import WhatsappTemplateBubble from './bubbles/WhatsappTemplate.vue';
import WhatsappFlowResponseBubble from './bubbles/WhatsappFlowResponse.vue';

import MessageError from './MessageError.vue';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
import { useBranding } from 'shared/composables/useBranding';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

/**
 * @typedef {Object} Attachment
 * @property {number} id - Unique identifier for the attachment
 * @property {number} messageId - ID of the associated message
 * @property {'image'|'audio'|'video'|'file'|'location'|'fallback'|'share'|'story_mention'|'contact'|'ig_reel'} fileType - Type of the attachment (file or image)
 * @property {number} accountId - ID of the associated account
 * @property {string|null} extension - File extension
 * @property {string} dataUrl - URL to access the full attachment data
 * @property {string} thumbUrl - URL to access the thumbnail version
 * @property {number} fileSize - Size of the file in bytes
 * @property {number|null} width - Width of the image if applicable
 * @property {number|null} height - Height of the image if applicable
 */

/**
 * @typedef {Object} Sender
 * @property {Object} additional_attributes - Additional attributes of the sender
 * @property {Object} custom_attributes - Custom attributes of the sender
 * @property {string} email - Email of the sender
 * @property {number} id - ID of the sender
 * @property {string|null} identifier - Identifier of the sender
 * @property {string} name - Name of the sender
 * @property {string|null} phone_number - Phone number of the sender
 * @property {string} thumbnail - Thumbnail URL of the sender
 * @property {string} type - Type of sender
 */

/**
 * @typedef {Object} ContentAttributes
 * @property {string} externalError - an error message to be shown if the message failed to send
 */

/**
 * @typedef {Object} Props
 * @property {('sent'|'delivered'|'read'|'failed'|'progress')} status - The delivery status of the message
 * @property {ContentAttributes} [contentAttributes={}] - Additional attributes of the message content
 * @property {Attachment[]} [attachments=[]] - The attachments associated with the message
 * @property {Sender|null} [sender=null] - The sender information
 * @property {boolean} [private=false] - Whether the message is private
 * @property {number|null} [senderId=null] - The ID of the sender
 * @property {number} createdAt - Timestamp when the message was created
 * @property {number} currentUserId - The ID of the current user
 * @property {number} id - The unique identifier for the message
 * @property {number} messageType - The type of message (must be one of MESSAGE_TYPES)
 * @property {string|null} [error=null] - Error message if the message failed to send
 * @property {string|null} [senderType=null] - The type of the sender
 * @property {string} content - The message content
 * @property {boolean} [groupWithNext=false] - Whether the message should be grouped with the next message
 * @property {Object|null} [inReplyTo=null] - The message to which this message is a reply
 * @property {boolean} [isEmailInbox=false] - Whether the message is from an email inbox
 * @property {number} conversationId - The ID of the conversation to which the message belongs
 * @property {number} inboxId - The ID of the inbox to which the message belongs
 */

// eslint-disable-next-line vue/define-macros-order
const props = defineProps({
  id: { type: Number, required: true },
  messageType: {
    type: Number,
    required: true,
    validator: value => Object.values(MESSAGE_TYPES).includes(value),
  },
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
  attachments: { type: Array, default: () => [] },
  call: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  content: { type: String, default: null },
  contentAttributes: { type: Object, default: () => ({}) },
  contentType: {
    type: String,
    default: 'text',
    validator: value => Object.values(CONTENT_TYPES).includes(value),
  },
  conversationId: { type: Number, required: true },
  createdAt: { type: Number, required: true }, // eslint-disable-line vue/no-unused-properties
  currentUserId: { type: Number, required: true }, // eslint-disable-line vue/no-unused-properties
  groupWithNext: { type: Boolean, default: false },
  inboxId: { type: Number, default: null }, // eslint-disable-line vue/no-unused-properties
  inboxSupportsReplyTo: { type: Object, default: () => ({}) },
  inReplyTo: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  isEmailInbox: { type: Boolean, default: false },
  private: { type: Boolean, default: false },
  additionalAttributes: { type: Object, default: () => ({}) }, // eslint-disable-line vue/no-unused-properties
  sender: { type: Object, default: null },
  senderId: { type: Number, default: null },
  senderType: { type: String, default: null },
  sourceId: { type: String, default: '' }, // eslint-disable-line vue/no-unused-properties
});

const emit = defineEmits(['retry']);

const contextMenuPosition = ref({});
const showReplyTargetFlash = ref(false);
const replyTargetFading = ref(false);
let replyFlashTimer = null;
let replyFlashFrame = null;
const showContextMenu = ref(false);
const { t } = useI18n();
const route = useRoute();
const inboxGetter = useMapGetter('inboxes/getInbox');
const inbox = computed(() => inboxGetter.value(props.inboxId) || {});
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const { replaceInstallationName } = useBranding();

const accountId = computed(() => Number(route.params.accountId));
const hasInternalTasks = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.INTERNAL_TASKS)
);

const isCaptainMessage = computed(() => {
  const senderType = props.sender?.type ?? props.senderType;
  return senderType === SENDER_TYPES.CAPTAIN_ASSISTANT;
});

/**
 * Computes the message variant based on props
 * @type {import('vue').ComputedRef<'user'|'agent'|'activity'|'private'|'bot'|'template'>}
 */
const variant = computed(() => {
  if (props.private) return MESSAGE_VARIANTS.PRIVATE;

  if (props.isEmailInbox) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) {
      return MESSAGE_VARIANTS.EMAIL;
    }
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return MESSAGE_VARIANTS.EMAIL;
  }

  if (props.status === MESSAGE_STATUS.FAILED) return MESSAGE_VARIANTS.ERROR;
  if (props.contentAttributes?.isUnsupported)
    return MESSAGE_VARIANTS.UNSUPPORTED;

  if (props.contentAttributes?.externalEcho) {
    return MESSAGE_VARIANTS.AGENT;
  }

  const isBot =
    props.sender?.type === SENDER_TYPES.AGENT_BOT ||
    props.senderType === SENDER_TYPES.AGENT_BOT ||
    (!props.sender && !props.additionalAttributes?.senderName);
  if (isBot && props.messageType === MESSAGE_TYPES.OUTGOING) {
    return MESSAGE_VARIANTS.BOT;
  }

  const variants = {
    [MESSAGE_TYPES.INCOMING]: MESSAGE_VARIANTS.USER,
    [MESSAGE_TYPES.ACTIVITY]: MESSAGE_VARIANTS.ACTIVITY,
    [MESSAGE_TYPES.OUTGOING]: MESSAGE_VARIANTS.AGENT,
    [MESSAGE_TYPES.TEMPLATE]: MESSAGE_VARIANTS.TEMPLATE,
  };

  return variants[props.messageType] || MESSAGE_VARIANTS.USER;
});

const isBotOrAgentMessage = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) {
    return false;
  }
  // if an outgoing message is still processing, then it's definitely a
  // message sent by the current user
  if (
    props.status === MESSAGE_STATUS.PROGRESS &&
    props.messageType === MESSAGE_TYPES.OUTGOING
  ) {
    return true;
  }
  const senderId = props.senderId ?? props.sender?.id;
  const senderType = props.sender?.type ?? props.senderType;

  if (!senderType || !senderId) {
    return true;
  }

  if (
    [SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT].includes(
      senderType
    )
  ) {
    return true;
  }

  return senderType.toLowerCase() === SENDER_TYPES.USER.toLowerCase();
});

/**
 * Computes the message orientation based on sender type and message type
 * @returns {import('vue').ComputedRef<'left'|'right'|'center'>} The computed orientation
 */
const orientation = computed(() => {
  if (isBotOrAgentMessage.value) {
    return ORIENTATION.RIGHT;
  }

  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return ORIENTATION.CENTER;

  return ORIENTATION.LEFT;
});

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const gridClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'grid grid-cols-1fr',
    [ORIENTATION.RIGHT]: 'grid grid-cols-[1fr_24px]',
  };

  return map[orientation.value];
});

const gridTemplate = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: `
      "bubble"
      "meta"
    `,
    [ORIENTATION.RIGHT]: `
      "bubble avatar"
      "meta spacer"
    `,
  };

  return map[orientation.value];
});

const shouldGroupWithNext = computed(() => {
  if (props.status === MESSAGE_STATUS.FAILED) return false;

  return props.groupWithNext;
});

const shouldShowAvatar = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return false;
  if (orientation.value === ORIENTATION.LEFT) return false;

  return true;
});

const componentToRender = computed(() => {
  if (props.isEmailInbox && !props.private) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) return EmailBubble;
  }

  if (props.contentAttributes?.whatsappFlowResponse) {
    return WhatsappFlowResponseBubble;
  }

  if (props.contentType === CONTENT_TYPES.INPUT_CSAT) {
    return CSATBubble;
  }

  if (
    [CONTENT_TYPES.INPUT_SELECT, CONTENT_TYPES.FORM].includes(props.contentType)
  ) {
    return FormBubble;
  }

  if (props.contentType === CONTENT_TYPES.VOICE_CALL) {
    return VoiceCallBubble;
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return EmailBubble;
  }

  if (props.contentAttributes?.isUnsupported) {
    return UnsupportedBubble;
  }

  if (
    variant.value === MESSAGE_VARIANTS.USER &&
    props.contentAttributes?.referral
  ) {
    return TextBubble;
  }

  if (props.contentAttributes.type === 'dyte') {
    return DyteBubble;
  }

  if (
    props.messageType === MESSAGE_TYPES.OUTGOING &&
    !props.private &&
    !props.contentAttributes.deleted &&
    props.contentType === CONTENT_TYPES.TEXT &&
    inbox.value.channel_type === 'Channel::Whatsapp'
  ) {
    if (props.additionalAttributes.whatsappFlow) return WhatsappFlowSentBubble;
    if (
      props.contentAttributes.whatsappTemplate ||
      props.additionalAttributes.templateParams?.name
    ) {
      return WhatsappTemplateBubble;
    }
  }

  const instagramSharedTypes = [
    ATTACHMENT_TYPES.STORY_MENTION,
    ATTACHMENT_TYPES.IG_STORY,
    ATTACHMENT_TYPES.IG_STORY_REPLY,
    ATTACHMENT_TYPES.IG_POST,
  ];
  if (instagramSharedTypes.includes(props.contentAttributes.imageType)) {
    return InstagramStoryBubble;
  }

  if (Array.isArray(props.attachments) && props.attachments.length === 1) {
    const fileType = props.attachments[0].fileType;

    if (fileType === ATTACHMENT_TYPES.FALLBACK) return FallbackBubble;

    if (!props.content) {
      if (fileType === ATTACHMENT_TYPES.IMAGE) return ImageBubble;
      if (fileType === ATTACHMENT_TYPES.FILE) return FileBubble;
      if (fileType === ATTACHMENT_TYPES.AUDIO) return AudioBubble;
      if (fileType === ATTACHMENT_TYPES.VIDEO) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.IG_REEL) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.EMBED) return EmbedBubble;
      if (fileType === ATTACHMENT_TYPES.LOCATION) return LocationBubble;
    }
    // Attachment content is the name of the contact
    if (fileType === ATTACHMENT_TYPES.CONTACT) return ContactBubble;
  }

  if (props.private && props.contentAttributes.captainHandoff) {
    return CaptainHandoffBubble;
  }

  return TextBubble;
});

const shouldShowContextMenu = computed(() => {
  return !props.contentAttributes?.isUnsupported;
});

const isBubble = computed(() => {
  return props.messageType !== MESSAGE_TYPES.ACTIVITY;
});

const isMessageDeleted = computed(() => {
  return props.contentAttributes?.deleted;
});

const shouldShowWhatsappReferral = computed(
  () =>
    variant.value === MESSAGE_VARIANTS.USER &&
    !!props.contentAttributes?.referral
);

const payloadForContextMenu = computed(() => {
  return {
    id: props.id,
    content_attributes: props.contentAttributes,
    content: props.content,
    conversation_id: props.conversationId,
  };
});

const contextMenuEnabledOptions = computed(() => {
  const hasText = !!props.content;
  const hasAttachments = !!(props.attachments && props.attachments.length > 0);

  const isOutgoing = props.messageType === MESSAGE_TYPES.OUTGOING;
  const isFailedOrProcessing =
    props.status === MESSAGE_STATUS.FAILED ||
    props.status === MESSAGE_STATUS.PROGRESS;

  return {
    copy: hasText,
    delete:
      (hasText || hasAttachments) &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
    cannedResponse: isOutgoing && hasText && !isMessageDeleted.value,
    copyLink: !isFailedOrProcessing,
    translate: !isFailedOrProcessing && !isMessageDeleted.value && hasText,
    replyTo:
      !props.private &&
      props.inboxSupportsReplyTo.outgoing &&
      !isFailedOrProcessing,
    privateNote:
      !props.private && !isFailedOrProcessing && !isMessageDeleted.value,
    createTask:
      hasInternalTasks.value &&
      !props.private &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
    report:
      isOnChatwootCloud.value &&
      isCaptainMessage.value &&
      !isMessageDeleted.value,
  };
});

const shouldRenderMessage = computed(() =>
  isMessageRenderable(props, shouldShowWhatsappReferral.value)
);

function openContextMenu(e) {
  const shouldSkipContextMenu =
    e.target?.classList.contains('skip-context-menu') ||
    ['a', 'img'].includes(e.target?.tagName.toLowerCase());
  if (shouldSkipContextMenu || getSelection().toString()) {
    return;
  }

  e.preventDefault();
  if (e.type === 'contextmenu') {
    useTrack(ACCOUNT_EVENTS.OPEN_MESSAGE_CONTEXT_MENU);
  }
  contextMenuPosition.value = {
    x: e.pageX || e.clientX,
    y: e.pageY || e.clientY,
  };
  showContextMenu.value = true;
}

function closeContextMenu() {
  showContextMenu.value = false;
  contextMenuPosition.value = { x: null, y: null };
}

function handleReplyTo() {
  const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
  const { conversationId, id: replyTo } = props;

  LocalStorage.updateJsonStore(replyStorageKey, conversationId, replyTo);
  emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, props);
}

// The menu remains the single source of reply eligibility.
const canReply = computed(
  () =>
    isBubble.value &&
    shouldShowContextMenu.value &&
    contextMenuEnabledOptions.value.replyTo
);
const {
  isSwiping,
  swipeClass,
  onTouchStart,
  onTouchMove,
  onTouchEnd,
  onTouchCancel,
} = useSwipeToReply({ enabled: canReply, onReply: handleReplyTo });

function replyOnDoubleClick(event) {
  if (
    !canReply.value ||
    event.button !== 0 ||
    event.target.closest(REPLY_INTERACTIVE_SELECTOR)
  )
    return;
  const selection = window.getSelection();
  const selectedNode = selection?.anchorNode;
  const selectedElement =
    selectedNode?.nodeType === Node.ELEMENT_NODE
      ? selectedNode
      : selectedNode?.parentElement;
  if (selection?.toString() && selectedElement?.closest('pre, code')) return;
  selection?.removeAllRanges();
  handleReplyTo();
}

const avatarInfo = computed(() => {
  if (props.contentAttributes?.externalEcho) {
    const { name, avatar_url, channel_type, medium, voice_enabled } =
      inbox.value;
    const iconName = avatar_url
      ? null
      : getInboxIconByType(channel_type, medium, 'fill', voice_enabled);
    return {
      name: iconName ? '' : name || t('CONVERSATION.NATIVE_APP'),
      src: avatar_url || '',
      iconName,
    };
  }

  // If no sender, check for Slack (or other integration) sender info
  if (!props.sender) {
    const { senderName, senderAvatarUrl } = props.additionalAttributes || {};
    if (senderName) {
      return { name: senderName, src: senderAvatarUrl ?? '' };
    }
    return { name: t('CONVERSATION.SYSTEM'), src: '' };
  }

  const { sender } = props;
  const { name, type, avatarUrl, thumbnail } = sender || {};

  // If sender type is agent bot, use avatarUrl
  if ([SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT].includes(type)) {
    return {
      name: name ?? '',
      src: avatarUrl ?? '',
    };
  }

  // For all other senders, use thumbnail
  return {
    name: name ?? '',
    src: thumbnail ?? '',
  };
});

const avatarTooltip = computed(() => {
  if (props.contentAttributes?.externalEcho) {
    return replaceInstallationName(t('CONVERSATION.NATIVE_APP_ADVISORY'));
  }
  if (avatarInfo.value.name === '') return '';
  return `${t('CONVERSATION.SENT_BY')} ${avatarInfo.value.name}`;
});

const showReplyFlash = () => {
  showReplyTargetFlash.value = false;
  clearTimeout(replyFlashTimer);
  cancelAnimationFrame(replyFlashFrame);
  replyFlashFrame = requestAnimationFrame(() => {
    showReplyTargetFlash.value = true;
    replyTargetFading.value = false;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      replyFlashTimer = setTimeout(() => {
        showReplyTargetFlash.value = false;
      }, 1600);
      return;
    }
    replyFlashTimer = setTimeout(() => {
      replyTargetFading.value = true;
      replyFlashTimer = setTimeout(() => {
        showReplyTargetFlash.value = false;
      }, 1450);
    }, 150);
  });
};

const onHighlightMessage = ({ messageId } = {}) => {
  clearTimeout(replyFlashTimer);
  cancelAnimationFrame(replyFlashFrame);
  showReplyTargetFlash.value = false;
  if (Number(messageId) === Number(props.id)) showReplyFlash();
};

onMounted(() => {
  emitter.on(BUS_EVENTS.HIGHLIGHT_MESSAGE, onHighlightMessage);
  if (Number(route.query.messageId) === Number(props.id)) showReplyFlash();
});
onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.HIGHLIGHT_MESSAGE, onHighlightMessage);
  clearTimeout(replyFlashTimer);
  cancelAnimationFrame(replyFlashFrame);
});

provideMessageContext({
  ...toRefs(props),
  isPrivate: computed(() => props.private),
  variant,
  orientation,
  isBotOrAgentMessage,
  shouldGroupWithNext,
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="shouldRenderMessage"
    :id="`message${props.id}`"
    class="flex w-full min-w-0 overflow-x-clip message-bubble-container"
    :data-message-id="props.id"
    :class="[flexOrientationClass, shouldGroupWithNext ? 'mb-0.5' : 'mb-2']"
  >
    <div v-if="variant === MESSAGE_VARIANTS.ACTIVITY" class="w-full">
      <ActivityBubble :content="content" />
    </div>
    <div
      v-else
      :class="[
        gridClass,
        {
          'gap-y-2': contentAttributes.externalError,
          'w-full': variant === MESSAGE_VARIANTS.EMAIL,
        },
      ]"
      class="gap-x-2"
      :style="{
        gridTemplateAreas: gridTemplate,
      }"
    >
      <div
        v-if="!shouldGroupWithNext && shouldShowAvatar"
        v-tooltip.left-end="avatarTooltip"
        class="[grid-area:avatar] flex items-end"
      >
        <Avatar v-bind="avatarInfo" :size="24" />
      </div>
      <div
        class="[grid-area:bubble] flex min-w-0"
        :class="{
          'ms-8 justify-end': orientation === ORIENTATION.RIGHT,
          'me-8': orientation === ORIENTATION.LEFT,
        }"
        @contextmenu="openContextMenu($event)"
      >
        <div
          class="relative flex min-w-0 max-w-full group/reply"
          :class="{ 'w-full': variant === MESSAGE_VARIANTS.EMAIL }"
        >
          <div
            data-reply-surface
            class="relative flex min-w-0 max-w-full rounded-[0.875rem] transition-[box-shadow,transform] motion-reduce:transition-none"
            :class="[
              swipeClass,
              {
                'rounded-es-none': orientation === ORIENTATION.LEFT,
                'rounded-ee-none': orientation === ORIENTATION.RIGHT,
              },
              showReplyTargetFlash
                ? [
                    'after:absolute after:inset-0 after:pointer-events-none after:rounded-[inherit] after:bg-n-teal-9/10 after:ring-2 after:ring-n-teal-9/50 after:transition-opacity motion-reduce:after:transition-none',
                    replyTargetFading
                      ? 'duration-[1450ms] after:opacity-0 after:duration-[1450ms]'
                      : 'duration-150 after:opacity-100 after:duration-150',
                  ]
                : 'after:absolute after:inset-0 after:pointer-events-none after:rounded-[inherit] after:bg-n-teal-9/10 after:ring-2 after:ring-n-teal-9/50 after:opacity-0 after:transition-opacity after:duration-[1450ms] motion-reduce:after:transition-none',
              isSwiping ? 'transition-none' : '',
              variant === MESSAGE_VARIANTS.EMAIL ? 'w-full' : '',
            ]"
            @dblclick="replyOnDoubleClick"
            @touchstart="onTouchStart"
            @touchmove="onTouchMove"
            @touchend="onTouchEnd"
            @touchcancel="onTouchCancel"
          >
            <Component :is="componentToRender" />
          </div>
          <Button
            v-if="canReply"
            data-reply-button
            type="button"
            intent="tertiary"
            icon="i-lucide-reply"
            :aria-label="$t('CONVERSATION.REPLYBOX.REPLY')"
            class="absolute top-1/2 -translate-y-1/2 !h-8 !w-8 !p-0 !rounded-full !bg-n-solid-3 hover:enabled:!bg-n-solid-3 !text-n-slate-12 shadow-md outline outline-1 outline-n-strong transition-opacity duration-150 before:absolute before:-inset-x-3 before:-inset-y-1 before:content-[''] focus-visible:ring-2 focus-visible:ring-n-brand motion-reduce:transition-none"
            :class="[
              isSwiping
                ? 'start-0'
                : orientation === ORIENTATION.RIGHT
                  ? '-start-11'
                  : '-end-11',
              isSwiping
                ? 'opacity-100 pointer-events-none'
                : 'opacity-0 pointer-events-none md:group-hover/reply:opacity-100 md:group-hover/reply:pointer-events-auto group-focus-within/reply:opacity-100 group-focus-within/reply:pointer-events-auto',
            ]"
            @click="handleReplyTo"
          />
        </div>
      </div>
      <MessageError
        v-if="contentAttributes.externalError"
        class="[grid-area:meta]"
        :class="flexOrientationClass"
        :error="contentAttributes.externalError"
        :channel-type="inbox.channel_type"
        @retry="emit('retry')"
      />
    </div>
    <div v-if="shouldShowContextMenu" class="context-menu-wrap">
      <ContextMenu
        v-if="isBubble"
        :context-menu-position="contextMenuPosition"
        :is-open="showContextMenu"
        :enabled-options="contextMenuEnabledOptions"
        :message="payloadForContextMenu"
        hide-button
        @open="openContextMenu"
        @close="closeContextMenu"
        @reply-to="handleReplyTo"
      />
    </div>
  </div>
</template>
