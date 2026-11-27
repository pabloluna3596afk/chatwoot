import { CONTENT_TYPES, MESSAGE_STATUS } from '../constants';

/**
 * Whether a message draws a bubble. Shared by Message.vue (render) and
 * MessageList.vue (grouping), so a hidden message never counts as the
 * "next" message of a group and steals the timestamp of the visible one.
 * @param {Object} message - camelCase message
 * @param {Boolean} [hasReferral] - WhatsApp referral card is shown
 * @returns {Boolean}
 */
export const isMessageRenderable = (message, hasReferral = false) => {
  if (!message) return false;
  const attributes = message.contentAttributes || {};

  return Boolean(
    message.attachments?.length > 0 ||
      message.content ||
      message.contentType === CONTENT_TYPES.INCOMING_EMAIL ||
      attributes.isUnsupported ||
      message.contentType === CONTENT_TYPES.INTEGRATIONS ||
      attributes.whatsappFlowResponse ||
      hasReferral ||
      message.status === MESSAGE_STATUS.FAILED ||
      attributes.externalError
  );
};
