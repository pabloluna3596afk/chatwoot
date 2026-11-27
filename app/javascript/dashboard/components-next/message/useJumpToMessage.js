import { nextTick, ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export const activeJumpMessageId = ref(null);
export const unavailableJumpTargets = ref(new Set());
export const jumpTargetKey = (conversationId, messageId) =>
  `${conversationId}:${messageId}`;

export function useJumpToMessage({
  getPanel,
  getMessages,
  getConversationId,
  fetchPreviousMessages,
  markProgrammaticScroll,
}) {
  let requestToken = 0;
  let stopScrolling = null;
  const isJumping = ref(false);

  const performJump = async ({ messageId, conversationId }, token) => {
    stopScrolling?.();
    emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId: null });
    activeJumpMessageId.value = null;
    const targetId = Number(messageId);
    const initialConversationId = getConversationId();
    const isCurrent = () =>
      token === requestToken &&
      Number(getConversationId()) === Number(initialConversationId);
    const panel = getPanel();
    if (!targetId || !panel) return 'unavailable';

    if (
      conversationId &&
      Number(conversationId) !== Number(initialConversationId)
    ) {
      return 'unavailable';
    }

    await nextTick();
    if (!isCurrent()) return 'cancelled';
    let target = panel.querySelector(`#message${targetId}`);
    if (!target) {
      const messages = getMessages();
      const firstMessageId = Number(messages[0]?.id);
      if (!firstMessageId || targetId >= firstMessageId) {
        unavailableJumpTargets.value.add(
          jumpTargetKey(initialConversationId, targetId)
        );
        return 'unavailable';
      }

      const heightBeforeLoad = panel.scrollHeight;
      const scrollTopBeforeLoad = panel.scrollTop;
      activeJumpMessageId.value = targetId;
      try {
        const result = await fetchPreviousMessages({
          conversationId: initialConversationId,
          after: targetId,
          // Include a known visible anchor to prove the range is complete,
          // even when private-note filtering hides the server's 1000-row cap.
          before: firstMessageId + 1,
          anchorId: firstMessageId,
          shouldApply: isCurrent,
        });
        if (isCurrent() && result?.limited) {
          activeJumpMessageId.value = null;
          return 'limited';
        }
      } catch {
        if (token === requestToken) activeJumpMessageId.value = null;
        return isCurrent() ? 'error' : 'cancelled';
      }

      if (
        token !== requestToken ||
        Number(getConversationId()) !== Number(initialConversationId)
      ) {
        if (token === requestToken) activeJumpMessageId.value = null;
        return 'cancelled';
      }

      await new Promise(resolve => {
        requestAnimationFrame(resolve);
      });
      if (!isCurrent()) {
        if (token === requestToken) activeJumpMessageId.value = null;
        return 'cancelled';
      }
      const heightDifference = panel.scrollHeight - heightBeforeLoad;
      if (heightDifference) {
        markProgrammaticScroll();
        panel.scrollTop = scrollTopBeforeLoad + heightDifference;
      }
      target = panel.querySelector(`#message${targetId}`);
      activeJumpMessageId.value = null;
      if (!target) {
        unavailableJumpTargets.value.add(
          jumpTargetKey(initialConversationId, targetId)
        );
        return 'unavailable';
      }
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
      const settled = reduceMotion
        ? Promise.resolve()
        : new Promise(resolve => {
            let timer;
            const finish = () => {
              clearTimeout(timer);
              panel.removeEventListener('scrollend', finish);
              stopScrolling = null;
              resolve();
            };
            timer = setTimeout(finish, 600);
            panel.addEventListener('scrollend', finish, { once: true });
            stopScrolling = () => {
              panel.scrollTo({ top: panel.scrollTop, behavior: 'instant' });
              finish();
            };
          });
      panel.scrollTo({
        top: nextTop,
        behavior: reduceMotion ? 'auto' : 'smooth',
      });
      await settled;
      if (!isCurrent()) return 'cancelled';
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
    stopScrolling?.();
    activeJumpMessageId.value = null;
    isJumping.value = false;
  };

  const jumpToMessage = async (payload = {}) => {
    requestToken += 1;
    const token = requestToken;
    isJumping.value = true;
    try {
      return await performJump(payload, token);
    } finally {
      if (token === requestToken) isJumping.value = false;
    }
  };

  return { jumpToMessage, cancel, isJumping };
}
