<script setup>
import { computed, onMounted, ref } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useToolbarOverflow } from 'dashboard/composables/useToolbarOverflow';
import FileUpload from 'vue-upload-component';
import * as ActiveStorage from 'activestorage';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import VideoCallButton from '../VideoCallButton.vue';
import RequestContactInfoButton from '../RequestContactInfoButton.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { sendCenterIcon } from 'dashboard/components-next/whatsapp/send-center/helpers';
import RecordingBar from './RecordingBar.vue';
import ComposerOverflowMenu from './ComposerOverflowMenu.vue';

const props = defineProps({
  isNote: {
    type: Boolean,
    default: false,
  },
  onSend: {
    type: Function,
    default: () => {},
  },
  sendButtonText: {
    type: String,
    default: '',
  },
  sendButtonShortcut: { type: String, default: '' },
  recordingAudioDurationText: {
    type: String,
    default: '00:00',
  },
  inbox: {
    type: Object,
    default: () => ({}),
  },
  showFileUpload: {
    type: Boolean,
    default: false,
  },
  showAudioRecorder: {
    type: Boolean,
    default: false,
  },
  onFileUpload: {
    type: Function,
    default: () => {},
  },
  toggleEmojiPicker: {
    type: Function,
    default: () => {},
  },
  toggleAudioRecorder: {
    type: Function,
    default: () => {},
  },
  toggleAudioRecorderPlayPause: {
    type: Function,
    default: () => {},
  },
  isRecordingAudio: {
    type: Boolean,
    default: false,
  },
  recordingAudioState: {
    type: String,
    default: '',
  },
  isSendDisabled: {
    type: Boolean,
    default: false,
  },
  isOnPrivateNote: {
    type: Boolean,
    default: false,
  },
  enableMultipleFileUpload: {
    type: Boolean,
    default: true,
  },
  enableWhatsAppTemplates: {
    type: Boolean,
    default: false,
  },
  enableCannedResponses: {
    type: Boolean,
    default: true,
  },
  enableContentTemplates: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: Number,
    required: true,
  },
  message: {
    type: String,
    default: '',
  },
  newConversationModalActive: {
    type: Boolean,
    default: false,
  },
  portalSlug: {
    type: String,
    required: true,
  },
  conversationType: {
    type: String,
    default: '',
  },
  showQuotedReplyToggle: {
    type: Boolean,
    default: false,
  },
  quotedReplyEnabled: {
    type: Boolean,
    default: false,
  },
  isEditorDisabled: {
    type: Boolean,
    default: false,
  },
  hasAttachments: { type: Boolean, default: false },
});
const emit = defineEmits([
  'toggleInsertArticle',
  'selectWhatsappTemplate',
  'selectCannedResponse',
  'selectContentTemplate',
  'toggleQuotedReply',
  'requestContactInfoTemplate',
]);
const { t } = useI18n();
const { setSignatureFlagForInbox, fetchSignatureFlagFromUISettings } =
  useUISettings();
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const uploadRef = ref(null);
const toolbarRef = ref(null);
const isPhone = useMediaQuery('(max-width: 767px)');
const channelType = computed(() => props.inbox.channel_type);
const isAWhatsAppChannel = computed(
  () =>
    channelType.value === INBOX_TYPES.WHATSAPP ||
    (channelType.value === INBOX_TYPES.TWILIO &&
      props.inbox.medium === 'whatsapp')
);
const templateButtonIcon = computed(() => sendCenterIcon(props.inbox));
const showAttachButton = computed(
  () => !props.isEditorDisabled && (props.showFileUpload || props.isNote)
);
const showAudioRecorderButton = computed(
  () =>
    !props.isEditorDisabled &&
    ![INBOX_TYPES.LINE, INBOX_TYPES.TIKTOK].includes(channelType.value) &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.VOICE_RECORDER
    ) &&
    props.showAudioRecorder
);
const showMicInSendSlot = computed(
  () =>
    isPhone.value &&
    showAudioRecorderButton.value &&
    !props.message.trim() &&
    !props.hasAttachments
);
const showTemplateInSendSlot = computed(
  () =>
    props.isEditorDisabled &&
    isAWhatsAppChannel.value &&
    (props.enableWhatsAppTemplates || props.enableContentTemplates)
);
const allowedFileTypes = computed(() => {
  if (props.isOnPrivateNote) return getAllowedFileTypesByChannel();
  const type =
    channelType.value === INBOX_TYPES.INSTAGRAM ||
    props.conversationType === 'instagram_direct_message'
      ? INBOX_TYPES.INSTAGRAM
      : channelType.value;
  return getAllowedFileTypesByChannel({
    channelType: type,
    medium: props.inbox.medium,
  });
});
const sendWithSignature = computed(() =>
  fetchSignatureFlagFromUISettings(channelType.value)
);
const signatureToggleTooltip = computed(() =>
  sendWithSignature.value
    ? t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
    : t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP')
);
const quotedReplyToggleTooltip = computed(() =>
  props.quotedReplyEnabled
    ? t('CONVERSATION.REPLYBOX.QUOTED_REPLY.DISABLE_TOOLTIP')
    : t('CONVERSATION.REPLYBOX.QUOTED_REPLY.ENABLE_TOOLTIP')
);
const stateLabel = enabled =>
  enabled
    ? t('CONVERSATION.REPLYBOX.SIGNATURE_ON')
    : t('CONVERSATION.REPLYBOX.SIGNATURE_OFF');
const audioRecorderPlayStopIcon = computed(() => {
  if (props.recordingAudioState === 'playing') return 'i-ph-pause';
  if (['paused', 'stopped'].includes(props.recordingAudioState))
    return 'i-ph-play';
  return 'i-ph-stop';
});
const selectTemplate = () => {
  if (props.enableContentTemplates) emit('selectContentTemplate');
  else emit('selectWhatsappTemplate');
};
const activateItem = key => {
  const actions = {
    template: selectTemplate,
    audio: props.toggleAudioRecorder,
    emoji: props.toggleEmojiPicker,
    quoted: () => emit('toggleQuotedReply'),
    canned: () => emit('selectCannedResponse'),
    article: () => emit('toggleInsertArticle'),
    signature: () =>
      setSignatureFlagForInbox(channelType.value, !sendWithSignature.value),
  };
  actions[key]();
};
const toolbarItems = computed(() =>
  [
    {
      key: 'attach',
      hideRank: 10,
      visible: showAttachButton.value,
      icon: 'i-ph-paperclip',
      label: t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON'),
    },
    {
      key: 'template',
      hideRank: 9,
      visible:
        (props.enableWhatsAppTemplates || props.enableContentTemplates) &&
        !showTemplateInSendSlot.value,
      icon: templateButtonIcon.value,
      label: t('WHATSAPP_TEMPLATES.SEND_CENTER.TITLE'),
    },
    {
      key: 'audio',
      hideRank: 8,
      visible: showAudioRecorderButton.value && !showMicInSendSlot.value,
      icon: 'i-ph-microphone',
      label: t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON'),
    },
    {
      key: 'emoji',
      hideRank: 7,
      visible: !props.isEditorDisabled,
      icon: 'i-ph-smiley-sticker',
      label: t('CONVERSATION.REPLYBOX.TIP_EMOJI_ICON'),
    },
    {
      key: 'contact',
      hideRank: 6,
      visible: !props.isOnPrivateNote,
      icon: 'i-ph-address-book',
      label: t('CONVERSATION.REQUEST_CONTACT_INFO.ACTION'),
    },
    {
      key: 'video',
      hideRank: 5,
      visible:
        [INBOX_TYPES.WEB, INBOX_TYPES.API].includes(channelType.value) &&
        !props.isOnPrivateNote &&
        !props.isEditorDisabled,
      icon: 'i-ph-video-camera',
      label: t('INTEGRATION_SETTINGS.DYTE.START_VIDEO_CALL_HELP_TEXT'),
    },
    {
      key: 'quoted',
      hideRank: 4,
      visible: props.showQuotedReplyToggle,
      icon: 'i-ph-quotes',
      label: quotedReplyToggleTooltip.value,
      state: stateLabel(props.quotedReplyEnabled),
    },
    {
      key: 'canned',
      hideRank: 3,
      visible:
        props.enableCannedResponses &&
        !props.isOnPrivateNote &&
        !props.isEditorDisabled,
      icon: 'i-lucide-text-quote',
      label: t('CONVERSATION.FOOTER.CANNED_RESPONSES'),
    },
    {
      key: 'article',
      hideRank: 2,
      visible: !!props.portalSlug,
      icon: 'i-ph-article-ny-times',
      label: t('HELP_CENTER.ARTICLE_SEARCH.OPEN_ARTICLE_SEARCH'),
    },
    {
      key: 'signature',
      hideRank: 1,
      visible: !props.isEditorDisabled && !props.isOnPrivateNote,
      icon: 'i-ph-signature',
      label: signatureToggleTooltip.value,
      state: stateLabel(sendWithSignature.value),
    },
  ].filter(item => item.visible)
);
const { hiddenKeys, hiddenItems, isMeasured } = useToolbarOverflow(
  toolbarRef,
  toolbarItems
);
const isHidden = key => hiddenKeys.value.includes(key);
const activateHiddenItem = key => {
  const element = toolbarRef.value.querySelector(
    `[data-toolbar-item="${key}"]`
  );
  if (key === 'attach') element.querySelector('input[type="file"]')?.click();
  else element.querySelector('button')?.click();
};
useKeyboardEvents({
  '$mod+Alt+KeyA': {
    action: () => {
      if (!props.isEditorDisabled)
        document.querySelector('#conversationAttachment')?.click();
    },
    allowOnFocusedInput: true,
  },
});
onMounted(() => ActiveStorage.start());
</script>

<template>
  <RecordingBar
    v-if="isRecordingAudio"
    :duration="recordingAudioDurationText || '00:00'"
    :play-stop-icon="audioRecorderPlayStopIcon"
    :send-label="sendButtonText"
    :send-disabled="isSendDisabled"
    :is-note="isNote"
    @cancel="toggleAudioRecorder"
    @play-pause="toggleAudioRecorderPlayPause"
    @send="onSend"
  />
  <div
    v-show="!isRecordingAudio"
    class="flex items-center gap-2 px-2.5 py-1.5"
    :class="{ 'is-note-mode': isNote }"
  >
    <div
      ref="toolbarRef"
      class="left-wrap flex min-w-0 flex-1 items-center gap-2"
      :class="{
        invisible: !isMeasured,
        'max-md:grow-0 max-md:basis-auto': showTemplateInSendSlot,
      }"
    >
      <template v-for="item in toolbarItems" :key="item.key">
        <span
          v-show="!isHidden(item.key)"
          :data-toolbar-item="item.key"
          class="inline-flex shrink-0 empty:hidden"
        >
          <FileUpload
            v-if="item.key === 'attach'"
            :ref="element => (uploadRef = element)"
            input-id="conversationAttachment"
            :size="4096 * 4096"
            :accept="allowedFileTypes"
            :multiple="enableMultipleFileUpload"
            :drop="!newConversationModalActive"
            :drop-directory="false"
            :data="{
              direct_upload_url: '/rails/active_storage/direct_uploads',
              direct_upload: true,
            }"
            @input-file="onFileUpload"
          >
            <NextButton
              v-tooltip.top-end="item.label"
              intent="tertiary"
              sm
              :icon="item.icon"
              :aria-label="item.label"
            />
          </FileUpload>
          <RequestContactInfoButton
            v-else-if="item.key === 'contact'"
            @request-template="emit('requestContactInfoTemplate')"
          />
          <VideoCallButton
            v-else-if="item.key === 'video'"
            :conversation-id="conversationId"
          />
          <NextButton
            v-else
            v-tooltip.top-end="item.label"
            intent="tertiary"
            sm
            :icon="item.icon"
            :aria-label="item.label"
            :aria-pressed="
              item.key === 'quoted' ? quotedReplyEnabled : undefined
            "
            :variant="
              item.key === 'quoted' && quotedReplyEnabled ? 'solid' : undefined
            "
            @click="activateItem(item.key)"
          />
        </span>
      </template>
      <ComposerOverflowMenu
        v-if="hiddenItems.length"
        :items="hiddenItems"
        @select="activateHiddenItem"
      />
    </div>
    <div
      class="right-wrap flex shrink-0"
      :class="{ 'max-md:flex-1': showTemplateInSendSlot }"
    >
      <NextButton
        v-if="showTemplateInSendSlot"
        intent="primary"
        sm
        :label="$t('CONVERSATION.REPLYBOX.SEND_TEMPLATE')"
        class="max-md:w-full"
        @click="selectTemplate"
      />
      <NextButton
        v-else-if="showMicInSendSlot"
        intent="primary"
        sm
        icon="i-ph-microphone"
        class="!rounded-full"
        :aria-label="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        @click="toggleAudioRecorder"
      />
      <NextButton
        v-else-if="isPhone"
        intent="primary"
        :color="isNote ? 'amber' : undefined"
        sm
        icon="i-lucide-send-horizontal"
        class="!rounded-full"
        :aria-label="sendButtonText"
        :disabled="isSendDisabled"
        @click="onSend"
      />
      <NextButton
        v-else
        intent="primary"
        :color="isNote ? 'amber' : undefined"
        type="submit"
        sm
        :aria-label="sendButtonText"
        :disabled="isSendDisabled"
        @click="onSend"
      >
        <span>{{ sendButtonText }}</span>
        <kbd class="max-md:hidden [@media(hover:none)]:hidden">{{
          sendButtonShortcut
        }}</kbd>
      </NextButton>
    </div>
  </div>
  <transition name="modal-fade">
    <div
      v-show="uploadRef && uploadRef.dropActive"
      class="flex fixed top-0 right-0 bottom-0 left-0 z-20 flex-col gap-2 justify-center items-center w-full h-full text-n-slate-12 bg-modal-backdrop-light dark:bg-modal-backdrop-dark"
    >
      <fluent-icon icon="cloud-backup" size="40" />
      <h4 class="text-2xl break-words text-n-slate-12">
        {{ $t('CONVERSATION.REPLYBOX.DRAG_DROP') }}
      </h4>
    </div>
  </transition>
</template>
