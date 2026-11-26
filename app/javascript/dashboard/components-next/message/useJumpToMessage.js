import { ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export const activeJumpMessageId = ref(null);

export function useJumpToMessage({
  getPanel,
  getMessages,
  getConversationId,
  fetchPreviousMessages,
  markProgrammaticScroll,
}) {
  let requestToken = 0;

  const jumpToMessage = async ({ messageId, conversationId } = {}) => {
    requestToken += 1;
    const token = requestToken;
    activeJumpMessageId.value = null;
    const targetId = Number(messageId);
    const initialConversationId = getConversationId();
    const panel = getPanel();
    if (!targetId || !panel) return 'unavailable';

    if (
      conversationId &&
      Number(conversationId) !== Number(initialConversationId)
    ) {
      return 'unavailable';
    }

    let target = document.getElementById(`message${targetId}`);
    if (!target) {
      const messages = getMessages();
      const firstMessageId = Number(messages[0]?.id);
      if (!firstMessageId || targetId >= firstMessageId) return 'unavailable';

      const heightBeforeLoad = panel.scrollHeight;
      const scrollTopBeforeLoad = panel.scrollTop;
      activeJumpMessageId.value = targetId;
      try {
        await fetchPreviousMessages({
          conversationId: initialConversationId,
          after: targetId,
          before: firstMessageId,
        });
      } catch {
        if (token === requestToken) activeJumpMessageId.value = null;
        return 'unavailable';
      }

      if (
        token !== requestToken ||
        Number(getConversationId()) !== Number(initialConversationId)
      ) {
        return 'cancelled';
      }

      await new Promise(resolve => {
        requestAnimationFrame(resolve);
      });
      const heightDifference = panel.scrollHeight - heightBeforeLoad;
      if (heightDifference) {
        markProgrammaticScroll();
        panel.scrollTop = scrollTopBeforeLoad + heightDifference;
      }
      target = document.getElementById(`message${targetId}`);
      activeJumpMessageId.value = null;
      if (!target) return 'unavailable';
    }

    if (token !== requestToken) return 'cancelled';
    const bubble = target.querySelector('[data-reply-surface]') || target;
    const panelRect = panel.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    const isVisible =
      targetRect.top >= panelRect.top && targetRect.bottom <= panelRect.bottom;

    if (!isVisible) {
      const nextTop = Math.max(
        0,
        Math.min(
          panel.scrollHeight - panel.clientHeight,
          panel.scrollTop +
            targetRect.top -
            panelRect.top -
            (panel.clientHeight - targetRect.height) / 2
        )
      );
      const reduceMotion = window.matchMedia(
        '(prefers-reduced-motion: reduce)'
      ).matches;
      markProgrammaticScroll();
      panel.scrollTo({
        top: nextTop,
        behavior: reduceMotion ? 'auto' : 'smooth',
      });
    }

    emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId: targetId });
    if (!bubble.hasAttribute('tabindex')) {
      bubble.setAttribute('tabindex', '-1');
      bubble.addEventListener(
        'blur',
        () => bubble.removeAttribute('tabindex'),
        { once: true }
      );
    }
    bubble.focus({ preventScroll: true });
    return 'found';
  };

  const cancel = () => {
    requestToken += 1;
    activeJumpMessageId.value = null;
  };

  return { jumpToMessage, cancel };
}
