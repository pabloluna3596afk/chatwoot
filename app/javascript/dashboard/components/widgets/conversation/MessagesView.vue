<script>
import { ref, computed, provide, nextTick, useTemplateRef } from 'vue';
import {
  useMediaQuery,
  useElementSize,
  useEventListener,
  useSessionStorage,
} from '@vueuse/core';
// composable
import { useLabelSuggestions } from 'dashboard/composables/useLabelSuggestions';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useContactConversationNavigation } from 'dashboard/composables/useContactConversationNavigation';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConversationLabelSuggestion from './conversation/LabelSuggestion.vue';
import ContactConversationLink from './ContactConversationLink.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CollapsedReplyBar from './CollapsedReplyBar.vue';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';
import ReferralBubble from 'dashboard/components-next/Conversation/ReferralBubble.vue';
import TypingDots from './TypingDots.vue';

// stores and apis
import { mapGetters } from 'vuex';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { getTypingUsersText } from '../../../helper/commons';
import { calculateScrollTop } from './helpers/scrollTopCalculationHelper';
import { useJumpToMessage } from 'next/message/useJumpToMessage';
import { useAlert } from 'dashboard/composables';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_POLICY } from 'shared/constants/links';
import wootConstants, {
  META_RESTRICTION_STATUS_URL,
} from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const BOTTOM_PIN_THRESHOLD = 80;

const FOLD_MOTION =
  'duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] motion-reduce:duration-0';
const FOLD_ACTIVE_CLASS = `transition-[grid-template-rows,opacity] [&>div]:overflow-hidden ${FOLD_MOTION}`;
const FOLD_HIDDEN_CLASS = '[--fold-rows:0fr] opacity-0';
const FOLD_TRANSITION = {
  enterActiveClass: FOLD_ACTIVE_CLASS,
  leaveActiveClass: FOLD_ACTIVE_CLASS,
  enterFromClass: FOLD_HIDDEN_CLASS,
  leaveToClass: FOLD_HIDDEN_CLASS,
};

export default {
  components: {
    MessageList,
    NextButton,
    ReplyBox,
    Banner,
    ConversationLabelSuggestion,
    ContactConversationLink,
    Spinner,
    CollapsedReplyBar,
    ResizableEditorWrapper,
    ReferralBubble,
    TypingDots,
  },
  mixins: [inboxMixin],
  setup() {
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const replyBoxRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);

    const {
      captainTasksEnabled,
      isLabelSuggestionFeatureEnabled,
      getLabelSuggestions,
    } = useLabelSuggestions();

    const {
      olderConversation,
      newerConversation,
      buildConversationPath,
      isReadingHistory,
      latestConversation,
      leaveReadingMode,
    } = useContactConversationNavigation();

    provide('contextMenuElementTarget', conversationPanelRef);

    const isReplyBoxCollapsed = useSessionStorage(
      SESSION_STORAGE_KEYS.REPLY_BOX_COLLAPSED,
      false
    );
    const isPhone = useMediaQuery('(max-width: 767px)');
    const hasReplyDraft = computed(() =>
      Boolean(
        replyBoxRef.value?.message?.trim() || replyBoxRef.value?.hasAttachments
      )
    );
    const isReplyFolded = computed(
      () =>
        !isPhone.value &&
        ((isReadingHistory.value && !hasReplyDraft.value) ||
          isReplyBoxCollapsed.value)
    );
    const canSendPublicReply = computed(
      () => replyBoxRef.value?.canSendPublicReply ?? true
    );
    const collapseReplyBox = () => {
      isReplyBoxCollapsed.value = true;
    };
    const showReplyBox = () => {
      isReplyBoxCollapsed.value = false;
      leaveReadingMode();
    };
    const revealReplyBox = mode => {
      if (!isReplyFolded.value) return;
      showReplyBox();
      nextTick(() => {
        const replyBox = replyBoxRef.value;
        if (mode && replyBox.replyType !== mode) replyBox.setReplyMode(mode);
        replyBox.messageEditor?.focusEditorInputField();
      });
    };
    useKeyboardEvents({
      'Alt+KeyL': {
        action: () => revealReplyBox(),
        allowOnFocusedInput: false,
      },
      'Alt+KeyP': {
        action: () => revealReplyBox(),
        allowOnFocusedInput: false,
      },
    });
    useEventListener(document, 'paste', event => {
      if (event.clipboardData?.files.length) revealReplyBox();
    });

    return {
      captainTasksEnabled,
      getLabelSuggestions,
      isLabelSuggestionFeatureEnabled,
      olderConversation,
      newerConversation,
      buildConversationPath,
      isReplyBoxCollapsed,
      isReplyFolded,
      isReadingHistory,
      latestConversation,
      collapseReplyBox,
      foldTransition: FOLD_TRANSITION,
      canSendPublicReply,
      replyBoxRef,
      showReplyBox,
      revealReplyBox,
      replyEditorModes: REPLY_EDITOR_MODES,
      conversationPanelRef,
      resizableEditorWrapperRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      heightBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      showScrollToLatest: false,
      isProgrammaticScroll: false,
      programmaticScrollTimer: null,
      messageJump: null,
      jumpAnnouncement: '',
      messageSentSinceOpened: false,
      labelSuggestions: [],
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      listLoadingStatus: 'getAllMessagesLoaded',
      currentAccountId: 'getCurrentAccountId',
      isMetaMessageSendingDisabled: 'globalConfig/isMetaMessageSendingDisabled',
    }),
    isOpen() {
      return this.currentChat?.status === wootConstants.STATUS_TYPE.OPEN;
    },
    shouldShowLabelSuggestions() {
      return (
        this.isOpen &&
        this.captainTasksEnabled &&
        this.isLabelSuggestionFeatureEnabled &&
        !this.messageSentSinceOpened
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        return filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    referralData() {
      return this.currentChat?.additional_attributes?.referral || null;
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious)
      );
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },
    isInstagramRestrictionBannerVisible() {
      return this.isMetaMessageSendingDisabled && this.isAnInstagramChannel;
    },
    showReplyWindowBanner() {
      return !this.currentChat.can_reply;
    },
    showDuplicateInstagramBanner() {
      return this.hasDuplicateInstagramInbox;
    },
    instagramRestrictionStatusUrl() {
      return META_RESTRICTION_STATUS_URL;
    },
    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    latestMessageBadge() {
      return this.unreadMessageCount > 99 ? '99+' : this.unreadMessageCount;
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
  },

  watch: {
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      this.messageJump.cancel();
      this.fetchAllAttachmentsFromCurrentChat();
      this.fetchSuggestions();
      this.messageSentSinceOpened = false;
      this.resetReplyEditorHeight();
    },
  },

  created() {
    this.messageJump = useJumpToMessage({
      getPanel: () => this.conversationPanel,
      getMessages: () => this.currentChat?.messages || [],
      getConversationId: () => this.currentChat?.id,
      fetchPreviousMessages: params =>
        this.$store.dispatch('fetchPreviousMessages', params),
      markProgrammaticScroll: () => this.markProgrammaticScroll(),
    });
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    // when a message is sent we set the flag to true this hides the label suggestions,
    // until the chat is changed and the flag is reset in the watch for currentChat
    emitter.on(BUS_EVENTS.MESSAGE_SENT, () => {
      this.messageSentSinceOpened = true;
    });
  },

  mounted() {
    this.addScrollListener();
    this.observeMessageListHeight();
    this.fetchAllAttachmentsFromCurrentChat();
    this.fetchSuggestions();
  },

  unmounted() {
    this.messageJump.cancel();
    clearTimeout(this.programmaticScrollTimer);
    this.messageListResizeObserver.disconnect();
    this.removeBusListeners();
    this.removeScrollListener();
  },

  methods: {
    observeMessageListHeight() {
      const panel = this.conversationPanel;
      let previousHeight = panel.clientHeight;
      this.messageListResizeObserver = new ResizeObserver(() => {
        const height = panel.clientHeight;
        if (height === previousHeight) return;

        // ResizeObserver runs after layout. Use the previous height so opening
        // the keyboard does not turn a pinned list into a scrolled-up list.
        const wasNearBottom =
          panel.scrollHeight - panel.scrollTop - previousHeight <=
          BOTTOM_PIN_THRESHOLD;
        previousHeight = height;
        if (wasNearBottom) this.scrollToBottom();
      });
      this.messageListResizeObserver.observe(panel);
    },
    async fetchSuggestions() {
      // start empty, this ensures that the label suggestions are not shown
      this.labelSuggestions = [];

      if (this.isLabelSuggestionDismissed()) {
        return;
      }

      // Early exit if conversation already has labels - no need to suggest more
      const existingLabels = this.currentChat?.labels || [];
      if (existingLabels.length > 0) return;

      if (!this.captainTasksEnabled || !this.isLabelSuggestionFeatureEnabled) {
        return;
      }

      this.labelSuggestions = await this.getLabelSuggestions();

      // once the labels are fetched, we need to scroll to bottom
      // but we need to wait for the DOM to be updated
      // so we use the nextTick method
      this.$nextTick(() => {
        // this param is added to route, telling the UI to navigate to the message
        // it is triggered by the SCROLL_TO_MESSAGE method
        // see setActiveChat on ConversationView.vue for more info
        const { messageId } = this.$route.query;

        // only trigger the scroll to bottom if the user has not scrolled
        // and there's no active messageId that is selected in view
        if (!messageId && !this.hasUserScrolled) {
          this.scrollToBottom();
        }
      });
    },
    isLabelSuggestionDismissed() {
      return LocalStorage.getFlag(
        LOCAL_STORAGE_KEYS.DISMISSED_LABEL_SUGGESTIONS,
        this.currentAccountId,
        this.currentChat.id
      );
    },
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    removeBusListeners() {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    },
    async onScrollToMessage(payload = {}) {
      this.hasUserScrolled = true;
      const result = await this.messageJump.jumpToMessage(payload);
      if (payload.source !== 'reply') this.makeMessagesRead();
      if (result === 'unavailable' && payload.source === 'reply') {
        useAlert(this.$t('CONVERSATION.REPLY_PREVIEW.ORIGINAL_UNAVAILABLE'));
        this.jumpAnnouncement = '';
      } else if (result === 'found') {
        this.jumpAnnouncement = '';
        this.$nextTick(() => {
          this.jumpAnnouncement = this.$t(
            'CONVERSATION.REPLY_PREVIEW.ORIGINAL_MESSAGE'
          );
        });
      }
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
    },
    scrollToBottom() {
      this.markProgrammaticScroll();
      let relevantMessages = [];

      // label suggestions are not part of the messages list
      // so we need to handle them separately
      let labelSuggestions =
        this.conversationPanel.querySelector('.label-suggestion');

      // if there are unread messages, scroll to the first unread message
      if (this.unreadMessageCount > 0) {
        // capturing only the unread messages
        relevantMessages =
          this.conversationPanel.querySelectorAll('.message--unread');
      } else if (labelSuggestions) {
        // when scrolling to the bottom, the label suggestions is below the last message
        // so we scroll there if there are no unread messages
        // Unread messages always take the highest priority
        relevantMessages = [labelSuggestions];
      } else {
        // if there are no unread messages or label suggestion, scroll to the last message
        // capturing last message from the messages list
        relevantMessages = Array.from(
          this.conversationPanel.querySelectorAll('.message--read')
        ).slice(-1);
      }

      this.conversationPanel.scrollTop = calculateScrollTop(
        this.conversationPanel.scrollHeight,
        this.$el.scrollHeight,
        relevantMessages
      );
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          const heightDifference =
            this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    handleScroll(e) {
      if (!this.isProgrammaticScroll) this.hasUserScrolled = true;
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);
      const { scrollHeight, scrollTop, clientHeight } = e.target;
      this.showScrollToLatest = scrollHeight - scrollTop - clientHeight > 240;
      if (!this.isProgrammaticScroll) this.fetchPreviousMessages(scrollTop);
    },
    markProgrammaticScroll() {
      this.isProgrammaticScroll = true;
      clearTimeout(this.programmaticScrollTimer);
      const panel = this.conversationPanel;
      const finish = () => {
        this.isProgrammaticScroll = false;
        clearTimeout(this.programmaticScrollTimer);
      };
      panel?.addEventListener('scrollend', finish, { once: true });
      this.programmaticScrollTimer = setTimeout(finish, 600);
    },
    scrollToLatest() {
      const panel = this.conversationPanel;
      if (!panel) return;
      this.markProgrammaticScroll();
      panel.scrollTo({ top: panel.scrollHeight, behavior: 'smooth' });
    },

    makeMessagesRead() {
      this.$store.dispatch('markMessagesRead', { id: this.currentChat.id });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
  >
    <div
      ref="topBannerRef"
      class="relative z-20 shrink-0 border-b border-n-weak bg-n-surface-1 empty:hidden"
    >
      <Banner
        v-if="isInstagramRestrictionBannerVisible"
        color-scheme="warning"
        class="!rounded-none !shadow-none !border-x-0 !border-t-0"
        :banner-message="$t('CONVERSATION.INSTAGRAM_RESTRICTION_BANNER')"
        :href-link="instagramRestrictionStatusUrl"
        :href-link-text="$t('CONVERSATION.INSTAGRAM_RESTRICTION_STATUS_LINK')"
      />
      <Banner
        v-if="showReplyWindowBanner"
        color-scheme="alert"
        class="!rounded-none !shadow-none !border-x-0 !border-t-0"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
      />
      <Banner
        v-if="showDuplicateInstagramBanner"
        color-scheme="alert"
        class="!rounded-none !shadow-none !border-x-0 !border-t-0"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel relative z-0 flex min-h-0 flex-shrink flex-grow basis-px flex-col overflow-y-auto m-0 pb-4"
      :current-user-id="currentUserId"
      :first-unread-id="unReadMessages[0]?.id"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :messages="getMessages"
      @retry="handleMessageRetry"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
        <ContactConversationLink
          v-if="olderConversation && listLoadingStatus"
          direction="older"
          :conversation="olderConversation"
          :to="buildConversationPath(olderConversation.id)"
        />
        <ReferralBubble v-if="referralData" :referral="referralData" />
      </template>
      <template #unreadBadge>
        <li
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ConversationLabelSuggestion
          v-if="shouldShowLabelSuggestions"
          :suggested-labels="labelSuggestions"
          :chat-labels="currentChat.labels"
          :conversation-id="currentChat.id"
        />
        <ContactConversationLink
          v-if="newerConversation"
          direction="newer"
          :conversation="newerConversation"
          :to="buildConversationPath(newerConversation.id)"
        />
      </template>
    </MessageList>
    <span class="sr-only" aria-live="polite" aria-atomic="true">
      {{ jumpAnnouncement }}
    </span>
    <div
      class="flex relative shrink-0 flex-col bg-n-surface-1 z-10 border-t border-n-weak max-md:pb-[env(safe-area-inset-bottom)]"
    >
      <Transition
        enter-active-class="transition duration-150 motion-reduce:transition-none"
        leave-active-class="transition duration-150 motion-reduce:transition-none"
        enter-from-class="opacity-0 translate-y-2"
        leave-to-class="opacity-0 translate-y-2"
      >
        <div
          v-if="showScrollToLatest"
          class="absolute -top-14 inset-x-0 mx-auto w-fit z-10 max-md:-top-12"
        >
          <NextButton
            intent="secondary"
            icon="i-lucide-arrow-down"
            class="!rounded-full !size-10 !bg-n-solid-1 hover:enabled:!bg-n-solid-1 text-n-slate-12 shadow-md hover:shadow-lg ring-1 ring-n-weak focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-label="$t('CONVERSATION.SCROLL_TO_LATEST')"
            @click="scrollToLatest"
          />
          <span
            v-if="unreadMessageCount > 0"
            class="absolute -top-1.5 -end-1.5 grid min-w-5 h-5 place-items-center rounded-full bg-n-brand px-1 text-xs font-medium text-white pointer-events-none"
            aria-hidden="true"
          >
            {{ latestMessageBadge }}
          </span>
        </div>
      </Transition>
      <div
        v-if="isAnyoneTyping"
        class="absolute flex items-center w-full h-0 -top-7"
      >
        <div
          class="flex py-2 pr-4 pl-5 shadow-md rounded-full bg-white dark:bg-n-solid-3 text-n-slate-11 text-xs font-semibold my-2.5 mx-auto"
        >
          {{ typingUserNames }}
          <TypingDots class="ltr:ml-2 rtl:mr-2" />
        </div>
      </div>
      <Transition v-bind="foldTransition">
        <div
          v-if="isReplyFolded"
          class="absolute inset-x-0 bottom-0 z-10 grid grid-rows-[var(--fold-rows,1fr)]"
        >
          <div class="min-h-0 min-w-0">
            <CollapsedReplyBar
              class="m-2"
              :reply-label="
                isReadingHistory
                  ? $t('CONVERSATION.CONTACT_HISTORY.REPLY_TO_OLDER')
                  : $t('CONVERSATION.REPLYBOX.REPLY')
              "
              :has-latest="isReadingHistory && Boolean(latestConversation)"
              :can-reply="canSendPublicReply"
              @open="revealReplyBox"
              @go-to-latest="
                $router.push(
                  buildConversationPath(latestConversation.id, {
                    keepFolderScope: false,
                  })
                )
              "
            />
          </div>
        </div>
      </Transition>
      <Transition v-bind="foldTransition">
        <div
          v-show="!isReplyFolded"
          class="grid grid-rows-[var(--fold-rows,1fr)]"
          :aria-hidden="isReplyFolded"
          :inert="isReplyFolded"
        >
          <div class="min-h-0 min-w-0">
            <ResizableEditorWrapper
              ref="resizableEditorWrapperRef"
              :container-height="Math.max(0, containerHeight - topBannerHeight)"
              @collapse="collapseReplyBox"
            >
              <ReplyBox
                ref="replyBoxRef"
                @toggle-editor-size="toggleReplyEditorSize"
                @collapse="collapseReplyBox"
              />
            </ResizableEditorWrapper>
          </div>
        </div>
      </Transition>
    </div>
  </div>
</template>
