import { useCopilotReply } from '../useCopilotReply';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useUISettings } from 'dashboard/composables/useUISettings';

vi.mock('dashboard/composables/useCaptain');
vi.mock('dashboard/composables/useUISettings');
vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));

describe('useCopilotReply', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useCaptain.mockReturnValue({
      processEvent: vi
        .fn()
        .mockResolvedValue({ message: 'Suggested response' }),
      followUp: vi.fn(),
      currentChat: { value: { id: 12 } },
      getTaskErrorMessage: errorType => `message for ${errorType}`,
    });
    useUISettings.mockReturnValue({ updateUISettings: vi.fn() });
  });

  it('requests and accepts a reply suggestion for the selected conversation', async () => {
    const { execute, generatedContent, accept } = useCopilotReply();

    await execute('reply_suggestion', '');

    expect(useCaptain().processEvent).toHaveBeenCalledWith(
      'reply_suggestion',
      '',
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(generatedContent.value).toBe('Suggested response');
    expect(accept()).toBe('Suggested response');
    expect(generatedContent.value).toBe('');
  });

  it.each([
    ['http_403', 'Plan required'],
    ['http_429', 'Quota resets on Nov 1'],
    ['http_502', 'Provider failed'],
  ])(
    'keeps the message for a returned %s error visible',
    async (errorType, message) => {
      useCaptain.mockReturnValue({
        processEvent: vi.fn().mockResolvedValue({ message: '', errorType }),
        followUp: vi.fn(),
        currentChat: { value: { id: 12 } },
        getTaskErrorMessage: () => message,
      });

      const { execute, errorMessage } = useCopilotReply();
      await execute('reply_suggestion', '');

      expect(errorMessage.value).toBe(message);
    }
  );

  it('maps a returned follow-up errorType to its user-facing message', async () => {
    useCaptain.mockReturnValue({
      processEvent: vi.fn().mockResolvedValue({
        message: 'Suggestion',
        followUpContext: { id: 1 },
      }),
      followUp: vi
        .fn()
        .mockResolvedValue({ message: '', errorType: 'http_429' }),
      currentChat: { value: { id: 12 } },
      getTaskErrorMessage: () => 'Quota resets on Nov 1',
    });

    const { execute, sendFollowUp, errorMessage } = useCopilotReply();
    await execute('reply_suggestion', '');
    await sendFollowUp('More concise');

    expect(errorMessage.value).toBe('Quota resets on Nov 1');
  });
});
