import { computed } from 'vue';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import TasksAPI from 'dashboard/api/captain/tasks';
import { CAPTAIN_ERROR_TYPES } from 'dashboard/composables/captain/constants';
import { MESSAGE_TYPE } from 'shared/constants/messages';

export function useCaptain() {
  const store = useStore();
  const { t, locale } = useI18n();
  const { isCloudFeatureEnabled, currentAccount } = useAccount();
  const { isEnterprise } = useConfig();
  const uiFlags = useMapGetter('accounts/getUIFlags');
  const currentChat = useMapGetter('getSelectedChat');
  const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
  const conversationId = computed(() => currentChat.value?.id);
  const draftKey = computed(
    () => `draft-${conversationId.value}-${replyMode.value}`
  );
  const draftMessage = useFunctionGetter('draftMessages/get', draftKey);

  // === Feature Flags ===
  const captainEnabled = computed(() => {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN);
  });

  const captainTasksEnabled = computed(() => {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_TASKS);
  });

  const latestPublicMessageIsIncoming = computed(() => {
    const latestPublicMessage = currentChat.value?.messages
      ?.filter(
        message =>
          !message.private &&
          [MESSAGE_TYPE.INCOMING, MESSAGE_TYPE.OUTGOING].includes(
            message.message_type
          )
      )
      .at(-1);

    return latestPublicMessage?.message_type === MESSAGE_TYPE.INCOMING;
  });

  // === Limits (Enterprise) ===
  const captainLimits = computed(() => {
    return currentAccount.value?.limits?.captain;
  });

  const documentLimits = computed(() => {
    if (captainLimits.value?.documents) {
      return useCamelCase(captainLimits.value.documents);
    }
    return null;
  });

  const responseLimits = computed(() => {
    if (captainLimits.value?.responses?.total_count != null) {
      return useCamelCase(captainLimits.value.responses);
    }
    return null;
  });

  const copilotLimits = computed(() => {
    if (captainLimits.value?.copilot?.total_count != null) {
      return useCamelCase(captainLimits.value.copilot);
    }
    return null;
  });

  const internalLimits = computed(() => {
    if (captainLimits.value?.internal?.total_count != null) {
      return useCamelCase(captainLimits.value.internal);
    }
    return null;
  });

  const internalLimitReached = computed(
    () => Number(internalLimits.value?.currentAvailable) === 0
  );
  const usagePeriodEnd = computed(
    () => currentAccount.value?.limits?.plan?.period_end
  );

  const storageLimits = computed(() => {
    if (captainLimits.value?.storage) {
      return useCamelCase(captainLimits.value.storage);
    }
    return null;
  });

  const isFetchingLimits = computed(() => uiFlags.value.isFetchingLimits);

  const fetchLimits = () => {
    if (isEnterprise) {
      store.dispatch('accounts/limits');
    }
  };

  // === Error Handling ===
  const getTaskErrorMessage = errorOrType => {
    const errorTypeStatus = String(errorOrType).startsWith(
      CAPTAIN_ERROR_TYPES.HTTP_PREFIX
    )
      ? Number(
          String(errorOrType).slice(CAPTAIN_ERROR_TYPES.HTTP_PREFIX.length)
        )
      : undefined;
    const status =
      errorOrType?.response?.status ?? errorTypeStatus ?? errorOrType;
    const errorCode = errorOrType?.response?.data?.error_code;

    if (status === 403 || errorCode === 403) {
      return t('INTEGRATION_SETTINGS.OPEN_AI.TASKS_PLAN_REQUIRED');
    }
    if (status === 429 || errorCode === 429) {
      const resetDate = usagePeriodEnd.value
        ? new Intl.DateTimeFormat(locale.value, { timeZone: 'UTC' }).format(
            new Date(usagePeriodEnd.value)
          )
        : '';
      if (resetDate) {
        return t('INTEGRATION_SETTINGS.OPEN_AI.TASKS_LIMIT_REACHED', {
          date: resetDate,
        });
      }
      return t('INTEGRATION_SETTINGS.OPEN_AI.TASKS_LIMIT_REACHED_NO_DATE');
    }
    return t('INTEGRATION_SETTINGS.OPEN_AI.TASKS_PROVIDER_ERROR');
  };

  /**
   * Handles API errors and displays appropriate error messages.
   * Silently returns for aborted requests.
   * @param {Error} error - The error object from the API call.
   */
  const handleAPIError = error => {
    if (
      error.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
      error.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR
    ) {
      return;
    }
    useAlert(getTaskErrorMessage(error));
  };

  /**
   * Classifies API error types for downstream analytics.
   * @param {Error} error
   * @returns {string}
   */
  const getErrorType = error => {
    if (
      error.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
      error.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR
    ) {
      return CAPTAIN_ERROR_TYPES.ABORTED;
    }
    if (error.response?.status) {
      return `${CAPTAIN_ERROR_TYPES.HTTP_PREFIX}${error.response.status}`;
    }
    return CAPTAIN_ERROR_TYPES.API_ERROR;
  };

  // === Task Methods ===
  /**
   * Rewrites content with a specific operation.
   * @param {string} content - The content to rewrite.
   * @param {string} operation - A supported rewrite operation.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The rewritten content and optional follow-up context.
   */
  const rewriteContent = async (content, operation, options = {}) => {
    try {
      const result = await TasksAPI.rewrite(
        {
          content: content || draftMessage.value,
          operation,
          conversationId: conversationId.value,
        },
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return {
        message: '',
        errorType: getErrorType(error),
        errorMessage: getTaskErrorMessage(error),
      };
    }
  };

  /**
   * Summarizes a conversation.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The summary and optional follow-up context.
   */
  const summarizeConversation = async (options = {}) => {
    try {
      const result = await TasksAPI.summarize(
        conversationId.value,
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return {
        message: '',
        errorType: getErrorType(error),
        errorMessage: getTaskErrorMessage(error),
      };
    }
  };

  /**
   * Gets a reply suggestion for the current conversation.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The reply suggestion and optional follow-up context.
   */
  const getReplySuggestion = async (options = {}) => {
    try {
      const result = await TasksAPI.replySuggestion(
        conversationId.value,
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return {
        message: '',
        errorType: getErrorType(error),
        errorMessage: getTaskErrorMessage(error),
      };
    }
  };

  /**
   * Sends a follow-up message to refine a previous AI task result.
   * @param {Object} options - The follow-up options.
   * @param {Object} options.followUpContext - The follow-up context from a previous task.
   * @param {string} options.message - The follow-up message/request from the user.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext: Object}>} The follow-up response and updated context.
   */
  const followUp = async ({ followUpContext, message, signal }) => {
    try {
      const result = await TasksAPI.followUp(
        { followUpContext, message, conversationId: conversationId.value },
        signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: updatedContext },
      } = result;
      return { message: generatedMessage, followUpContext: updatedContext };
    } catch (error) {
      handleAPIError(error);
      return {
        message: '',
        followUpContext,
        errorType: getErrorType(error),
        errorMessage: getTaskErrorMessage(error),
      };
    }
  };

  /**
   * Processes an AI event. Routes to the appropriate method based on type.
   * @param {string} [type='improve'] - The type of AI event to process.
   * @param {string} [content=''] - The content to process.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The generated message and optional follow-up context.
   */
  const processEvent = async (type = 'improve', content = '', options = {}) => {
    if (type === 'summarize') {
      return summarizeConversation(options);
    }
    if (type === 'reply_suggestion') {
      return getReplySuggestion(options);
    }
    // All other types are rewrite operations
    return rewriteContent(content, type, options);
  };

  return {
    // Feature flags
    captainEnabled,
    captainTasksEnabled,
    isEnterprise,
    latestPublicMessageIsIncoming,

    // Limits (Enterprise)
    captainLimits,
    documentLimits,
    responseLimits,
    copilotLimits,
    internalLimits,
    internalLimitReached,
    usagePeriodEnd,
    storageLimits,
    fetchLimits,
    isFetchingLimits,

    // Conversation context
    draftMessage,
    currentChat,

    // Task methods
    rewriteContent,
    summarizeConversation,
    getReplySuggestion,
    followUp,
    processEvent,
    getTaskErrorMessage,
  };
}
