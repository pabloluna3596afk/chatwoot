import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  activeJumpMessageId,
  unavailableJumpTargets,
  useJumpToMessage,
} from './useJumpToMessage';

const flushFrame = () =>
  new Promise(resolve => {
    requestAnimationFrame(resolve);
  });

const setup = ({ targetId = 20, targetRect, initialMessages } = {}) => {
  document.body.innerHTML = `
    <div id="panel">
      <div id="message${targetId}"><div data-reply-surface></div></div>
    </div>
  `;
  const panel = document.getElementById('panel');
  Object.defineProperties(panel, {
    clientHeight: { configurable: true, value: 400 },
    scrollHeight: { configurable: true, writable: true, value: 1200 },
    scrollTop: { configurable: true, writable: true, value: 100 },
  });
  panel.scrollTo = vi.fn();
  panel.getBoundingClientRect = () => ({ top: 0, bottom: 400 });
  const target = document.getElementById(`message${targetId}`);
  target.getBoundingClientRect =
    targetRect || (() => ({ top: 100, bottom: 160, height: 60 }));
  const fetchPreviousMessages = vi.fn();
  const markProgrammaticScroll = vi.fn();
  const getMessages = vi.fn(() => initialMessages || [{ id: 30 }]);
  let conversationId = 5;
  const service = useJumpToMessage({
    getPanel: () => panel,
    getMessages,
    getConversationId: () => conversationId,
    fetchPreviousMessages,
    markProgrammaticScroll,
  });
  return {
    ...service,
    panel,
    target,
    fetchPreviousMessages,
    markProgrammaticScroll,
    getMessages,
    setConversationId: value => {
      conversationId = value;
    },
  };
};

describe('useJumpToMessage', () => {
  beforeEach(() => {
    activeJumpMessageId.value = null;
    unavailableJumpTargets.value.clear();
    vi.stubGlobal('requestAnimationFrame', callback => setTimeout(callback, 0));
    vi.stubGlobal('matchMedia', () => ({ matches: false }));
    vi.spyOn(emitter, 'emit');
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    document.body.innerHTML = '';
  });

  it('only highlights and focuses a loaded target already visible', async () => {
    const { jumpToMessage, panel, target } = setup();
    expect(await jumpToMessage({ messageId: 20, source: 'reply' })).toBe(
      'found'
    );
    expect(panel.scrollTo).not.toHaveBeenCalled();
    expect(target.firstElementChild.getAttribute('tabindex')).toBe('-1');
    expect(document.activeElement).toBe(target.firstElementChild);
    expect(emitter.emit).toHaveBeenCalledWith(BUS_EVENTS.HIGHLIGHT_MESSAGE, {
      messageId: 20,
    });
  });

  it('highlights only after scrollend in a long thread', async () => {
    const { jumpToMessage, panel, fetchPreviousMessages } = setup({
      initialMessages: Array.from({ length: 60 }, (_, index) => ({
        id: index + 20,
      })),
      targetRect: () => ({ top: -700, bottom: -640, height: 60 }),
    });
    const pending = jumpToMessage({ messageId: 20 });
    await Promise.resolve();
    expect(emitter.emit).not.toHaveBeenCalledWith(
      BUS_EVENTS.HIGHLIGHT_MESSAGE,
      { messageId: 20 }
    );
    panel.dispatchEvent(new Event('scrollend'));
    expect(await pending).toBe('found');
    expect(fetchPreviousMessages).not.toHaveBeenCalled();
    expect(emitter.emit).toHaveBeenCalledWith(BUS_EVENTS.HIGHLIGHT_MESSAGE, {
      messageId: 20,
    });
  });

  it('the last click cancels a smooth scroll and owns the only highlight', async () => {
    const { jumpToMessage, panel, target } = setup({
      targetRect: () => ({ top: 700, bottom: 760, height: 60 }),
    });
    const first = jumpToMessage({ messageId: 20 });
    await Promise.resolve();
    target.id = 'message21';
    target.getBoundingClientRect = () => ({
      top: 100,
      bottom: 160,
      height: 60,
    });
    expect(await jumpToMessage({ messageId: 21 })).toBe('found');
    expect(await first).toBe('cancelled');
    expect(panel.scrollTo).toHaveBeenCalledWith({
      top: 100,
      behavior: 'instant',
    });
    expect(emitter.emit).not.toHaveBeenCalledWith(
      BUS_EVENTS.HIGHLIGHT_MESSAGE,
      { messageId: 20 }
    );
  });

  it('centers a loaded target outside the viewport with smooth motion', async () => {
    const { jumpToMessage, panel, markProgrammaticScroll } = setup({
      targetRect: () => ({ top: 700, bottom: 760, height: 60 }),
    });
    expect(await jumpToMessage({ messageId: 20 })).toBe('found');
    expect(markProgrammaticScroll).toHaveBeenCalledOnce();
    expect(panel.scrollTo).toHaveBeenCalledWith({
      top: 630,
      behavior: 'smooth',
    });
  });

  it('uses automatic motion when reduced motion is preferred', async () => {
    vi.stubGlobal('matchMedia', () => ({ matches: true }));
    const { jumpToMessage, panel } = setup({
      targetRect: () => ({ top: 700, bottom: 760, height: 60 }),
    });
    await jumpToMessage({ messageId: 20 });
    expect(panel.scrollTo).toHaveBeenCalledWith({ top: 630, behavior: 'auto' });
  });

  it('fetches one page around an older unloaded target, preserves scroll anchor, and jumps to it', async () => {
    const { jumpToMessage, panel, fetchPreviousMessages } = setup({
      targetId: 999,
      initialMessages: [{ id: 1000 }],
    });
    document.getElementById('message999').remove();
    fetchPreviousMessages.mockImplementation(async () => {
      panel.scrollHeight = 1500;
      panel.insertAdjacentHTML(
        'beforeend',
        '<div id="message999"><div data-reply-surface></div></div>'
      );
      document.getElementById('message999').getBoundingClientRect = () => ({
        top: 500,
        bottom: 560,
        height: 60,
      });
    });
    expect(await jumpToMessage({ messageId: 999, source: 'reply' })).toBe(
      'found'
    );
    expect(fetchPreviousMessages).toHaveBeenCalledOnce();
    expect(fetchPreviousMessages).toHaveBeenCalledWith({
      conversationId: 5,
      after: 999,
      before: 1001,
      anchorId: 1000,
      shouldApply: expect.any(Function),
    });
    expect(panel.scrollTop).toBe(400);
    expect(activeJumpMessageId.value).toBe(null);
  });

  it('reports a missing or private filtered target without jumping to the end', async () => {
    const { jumpToMessage, panel, fetchPreviousMessages } = setup({
      targetId: 10,
      initialMessages: [{ id: 20 }],
    });
    document.getElementById('message10').remove();
    fetchPreviousMessages.mockResolvedValue();
    expect(await jumpToMessage({ messageId: 10 })).toBe('unavailable');
    expect(fetchPreviousMessages).toHaveBeenCalledOnce();
    expect(panel.scrollTo).not.toHaveBeenCalled();
  });

  it('rejects a quote from another conversation', async () => {
    const { jumpToMessage, fetchPreviousMessages } = setup();
    expect(
      await jumpToMessage({ messageId: 20, conversationId: 6, source: 'reply' })
    ).toBe('unavailable');
    expect(fetchPreviousMessages).not.toHaveBeenCalled();
  });

  it('keeps a truncated history lookup retryable without moving or highlighting', async () => {
    const { jumpToMessage, target, panel, fetchPreviousMessages, isJumping } =
      setup();
    target.remove();
    fetchPreviousMessages.mockResolvedValue({ limited: true });

    expect(await jumpToMessage({ messageId: 20 })).toBe('limited');
    expect(fetchPreviousMessages).toHaveBeenCalledOnce();
    expect(panel.scrollTop).toBe(100);
    expect(panel.scrollTo).not.toHaveBeenCalled();
    expect(activeJumpMessageId.value).toBe(null);
    expect(isJumping.value).toBe(false);
    expect(unavailableJumpTargets.value.has('5:20')).toBe(false);
    expect(emitter.emit).not.toHaveBeenCalledWith(
      BUS_EVENTS.HIGHLIGHT_MESSAGE,
      { messageId: 20 }
    );
  });

  it('allows retry after a network failure and clears the loading state', async () => {
    const { jumpToMessage, target, panel, fetchPreviousMessages, isJumping } =
      setup();
    target.remove();
    fetchPreviousMessages.mockRejectedValue(new Error('offline'));

    expect(await jumpToMessage({ messageId: 20 })).toBe('error');
    expect(activeJumpMessageId.value).toBe(null);
    expect(isJumping.value).toBe(false);
    expect(unavailableJumpTargets.value.has('5:20')).toBe(false);

    panel.appendChild(target);
    expect(await jumpToMessage({ messageId: 20 })).toBe('found');
  });

  it('ignores an older pending request after a later click', async () => {
    const { jumpToMessage, fetchPreviousMessages, cancel } = setup({
      targetId: 10,
      initialMessages: [{ id: 20 }],
    });
    document.getElementById('message10').remove();
    let resolveFetch;
    fetchPreviousMessages.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveFetch = resolve;
        })
    );
    const firstJump = jumpToMessage({ messageId: 10 });
    await Promise.resolve();
    cancel();
    resolveFetch();
    await flushFrame();
    expect(await firstJump).toBe('cancelled');
    expect(activeJumpMessageId.value).toBe(null);
  });

  it('ignores a pending response after the selected conversation changes', async () => {
    const { jumpToMessage, fetchPreviousMessages, setConversationId, panel } =
      setup({ targetId: 10, initialMessages: [{ id: 20 }] });
    document.getElementById('message10').remove();
    let resolveFetch;
    fetchPreviousMessages.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveFetch = resolve;
        })
    );
    const pendingJump = jumpToMessage({ messageId: 10 });
    await Promise.resolve();
    setConversationId(8);
    resolveFetch();

    expect(await pendingJump).toBe('cancelled');
    expect(panel.scrollTo).not.toHaveBeenCalled();
  });
  it('waits for the pending DOM render before rejecting the first loaded message', async () => {
    const { jumpToMessage, target, panel, fetchPreviousMessages } = setup({
      initialMessages: [{ id: 20 }],
    });
    target.remove();
    queueMicrotask(() => panel.appendChild(target));
    expect(await jumpToMessage({ messageId: 20 })).toBe('found');
    expect(fetchPreviousMessages).not.toHaveBeenCalled();
  });

  it('does not find a target outside its own conversation panel', async () => {
    const { jumpToMessage, target, panel } = setup({
      initialMessages: [{ id: 20 }],
    });
    document.body.appendChild(target);
    expect(await jumpToMessage({ messageId: 20 })).toBe('unavailable');
    expect(panel.scrollTo).not.toHaveBeenCalled();
    expect(unavailableJumpTargets.value.has('5:20')).toBe(true);
  });

  it('clears loading when a conversation changes during the request', async () => {
    const { jumpToMessage, target, fetchPreviousMessages, setConversationId } =
      setup();
    target.remove();
    fetchPreviousMessages.mockImplementation(async () => setConversationId(9));
    expect(await jumpToMessage({ messageId: 20 })).toBe('cancelled');
    expect(activeJumpMessageId.value).toBe(null);
  });

  it('ignores failures from a cancelled request', async () => {
    const { jumpToMessage, target, fetchPreviousMessages, cancel } = setup();
    target.remove();
    let rejectFetch;
    fetchPreviousMessages.mockImplementation(
      () =>
        new Promise((resolve, reject) => {
          rejectFetch = reject;
        })
    );
    const pending = jumpToMessage({ messageId: 20 });
    await flushFrame();
    cancel();
    rejectFetch(new Error('offline'));
    expect(await pending).toBe('cancelled');
  });

  it('does not restore an obsolete anchor after cancellation during the render frame', async () => {
    const { jumpToMessage, target, panel, fetchPreviousMessages, cancel } =
      setup();
    target.remove();
    let frame;
    vi.stubGlobal('requestAnimationFrame', callback => {
      frame = callback;
      return 1;
    });
    fetchPreviousMessages.mockResolvedValue();
    const pending = jumpToMessage({ messageId: 20 });
    await Promise.resolve();
    await Promise.resolve();
    cancel();
    panel.scrollHeight = 1800;
    frame?.();
    expect(await pending).toBe('cancelled');
    expect(panel.scrollTop).toBe(100);
  });
});
