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
});
