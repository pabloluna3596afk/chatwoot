import { useCaptain } from '../useCaptain';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useI18n } from 'vue-i18n';
import TasksAPI from 'dashboard/api/captain/tasks';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useConfig');
vi.mock('vue-i18n');
vi.mock('dashboard/api/captain/tasks');
vi.mock('dashboard/helper/AnalyticsHelper/index', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    default: {
      track: vi.fn(),
    },
  };
});
vi.mock('dashboard/helper/AnalyticsHelper/events', () => ({
  CAPTAIN_EVENTS: {
    TEST_EVENT: 'captain_test_event',
  },
}));

describe('useCaptain', () => {
  const mockStore = {
    dispatch: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    useStore.mockReturnValue(mockStore);
    useFunctionGetter.mockReturnValue({ value: 'Draft message' });
    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'accounts/getUIFlags': { isFetchingLimits: false },
        getSelectedChat: { id: '123' },
        'draftMessages/getReplyEditorMode': 'reply',
      };
      return { value: mockValues[getter] };
    });
    useI18n.mockReturnValue({ t: vi.fn() });
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: { value: { limits: { captain: {} } } },
    });
    useConfig.mockReturnValue({
      isEnterprise: false,
    });
  });

  it('initializes computed properties correctly', async () => {
    const { captainEnabled, captainTasksEnabled, currentChat, draftMessage } =
      useCaptain();

    expect(captainEnabled.value).toBe(true);
    expect(captainTasksEnabled.value).toBe(true);
    expect(currentChat.value).toEqual({ id: '123' });
    expect(draftMessage.value).toBe('Draft message');
  });

  it('only exposes Copilot and internal meters when their limits are configured', () => {
    const withoutLimits = useCaptain();
    expect(withoutLimits.responseLimits.value).toBeNull();
    expect(withoutLimits.copilotLimits.value).toBeNull();
    expect(withoutLimits.internalLimits.value).toBeNull();

    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: {
        value: {
          limits: {
            captain: {
              responses: {
                total_count: null,
                consumed: 0,
                current_available: 1000000,
              },
              copilot: { total_count: 5, consumed: 2, current_available: 3 },
              internal: { total_count: 20, consumed: 6, current_available: 14 },
            },
          },
        },
      },
    });

    const withLimits = useCaptain();
    expect(withLimits.responseLimits.value).toBeNull();
    expect(withLimits.copilotLimits.value).toEqual({
      totalCount: 5,
      consumed: 2,
      currentAvailable: 3,
    });
    expect(withLimits.internalLimits.value).toEqual({
      totalCount: 20,
      consumed: 6,
      currentAvailable: 14,
    });
  });

  it('exposes the response meter only when a limit is configured', () => {
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: {
        value: {
          limits: {
            captain: {
              responses: {
                total_count: 200,
                consumed: 20,
                current_available: 180,
              },
            },
          },
        },
      },
    });

    expect(useCaptain().responseLimits.value).toEqual({
      totalCount: 200,
      consumed: 20,
      currentAvailable: 180,
    });
  });

  it('rewrites content', async () => {
    TasksAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten content', follow_up_context: { id: 'ctx1' } },
    });

    const { rewriteContent } = useCaptain();
    const result = await rewriteContent('Original content', 'improve', {});

    expect(TasksAPI.rewrite).toHaveBeenCalledWith(
      {
        content: 'Original content',
        operation: 'improve',
        conversationId: '123',
      },
      undefined
    );
    expect(result).toEqual({
      message: 'Rewritten content',
      followUpContext: { id: 'ctx1' },
    });
  });

  it('summarizes conversation', async () => {
    TasksAPI.summarize.mockResolvedValue({
      data: { message: 'Summary', follow_up_context: { id: 'ctx2' } },
    });

    const { summarizeConversation } = useCaptain();
    const result = await summarizeConversation({});

    expect(TasksAPI.summarize).toHaveBeenCalledWith('123', undefined);
    expect(result).toEqual({
      message: 'Summary',
      followUpContext: { id: 'ctx2' },
    });
  });

  it('gets reply suggestion', async () => {
    TasksAPI.replySuggestion.mockResolvedValue({
      data: { message: 'Reply suggestion', follow_up_context: { id: 'ctx3' } },
    });

    const { getReplySuggestion } = useCaptain();
    const result = await getReplySuggestion({});

    expect(TasksAPI.replySuggestion).toHaveBeenCalledWith('123', undefined);
    expect(result).toEqual({
      message: 'Reply suggestion',
      followUpContext: { id: 'ctx3' },
    });
  });

  it('sends follow-up message', async () => {
    TasksAPI.followUp.mockResolvedValue({
      data: {
        message: 'Follow-up response',
        follow_up_context: { id: 'ctx4' },
      },
    });

    const { followUp } = useCaptain();
    const result = await followUp({
      followUpContext: { id: 'ctx3' },
      message: 'Make it shorter',
    });

    expect(TasksAPI.followUp).toHaveBeenCalledWith(
      {
        followUpContext: { id: 'ctx3' },
        message: 'Make it shorter',
        conversationId: '123',
      },
      undefined
    );
    expect(result).toEqual({
      message: 'Follow-up response',
      followUpContext: { id: 'ctx4' },
    });
  });

  it('processes event and routes to correct method', async () => {
    TasksAPI.summarize.mockResolvedValue({
      data: { message: 'Summary' },
    });
    TasksAPI.replySuggestion.mockResolvedValue({
      data: { message: 'Reply' },
    });
    TasksAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten' },
    });

    const { processEvent } = useCaptain();

    // Test summarize
    await processEvent('summarize', '', {});
    expect(TasksAPI.summarize).toHaveBeenCalled();

    // Test reply_suggestion
    await processEvent('reply_suggestion', '', {});
    expect(TasksAPI.replySuggestion).toHaveBeenCalled();

    // Test rewrite (improve)
    await processEvent('improve', 'content', {});
    expect(TasksAPI.rewrite).toHaveBeenCalled();
  });
});
