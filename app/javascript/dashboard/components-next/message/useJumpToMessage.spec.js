import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { activeJumpMessageId, useJumpToMessage } from './useJumpToMessage';

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
      document.body.insertAdjacentHTML(
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
      before: 1000,
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
});
