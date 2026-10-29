import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ReplyTopPanel from './ReplyTopPanel.vue';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/useCaptain');
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

describe('ReplyTopPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useMapGetter.mockReturnValue({ value: 'reply' });
    useCaptain.mockReturnValue({
      captainTasksEnabled: ref(false),
      isEnterprise: true,
      latestPublicMessageIsIncoming: ref(false),
      internalLimitReached: ref(false),
      usagePeriodEnd: ref(null),
    });
  });

  it('keeps the AI menu visible on Enterprise and explains an outgoing last message', async () => {
    useCaptain.mockReturnValue({
      captainTasksEnabled: ref(true),
      isEnterprise: true,
      latestPublicMessageIsIncoming: ref(false),
      internalLimitReached: ref(false),
      usagePeriodEnd: ref(null),
    });
    const wrapper = mount(ReplyTopPanel, {
      props: { conversationId: 12 },
      global: {
        mocks: { $t: key => key },
        stubs: { EditorModeToggle: true, CopilotMenuBar: true },
      },
    });

    await wrapper.findAll('button')[0].trigger('click');

    expect(
      wrapper.findComponent({ name: 'CopilotMenuBar' }).props()
    ).toMatchObject({
      conversationId: 12,
      replySuggestionDisabledReason: 'incoming',
    });
  });

  it('shows the menu entry disabled when the plan does not include tasks', async () => {
    const wrapper = mount(ReplyTopPanel, {
      props: { conversationId: 12 },
      global: {
        mocks: { $t: key => key },
        stubs: { EditorModeToggle: true, CopilotMenuBar: true },
      },
    });

    await wrapper.findAll('button')[0].trigger('click');

    expect(
      wrapper
        .findComponent({ name: 'CopilotMenuBar' })
        .props('replySuggestionDisabledReason')
    ).toBe('plan');
  });

  it('passes the exhausted internal quota and UTC reset date to the menu', async () => {
    const periodEnd = '2026-11-01T00:00:00Z';
    useCaptain.mockReturnValue({
      captainTasksEnabled: ref(true),
      captainEnabled: true,
      isEnterprise: true,
      latestPublicMessageIsIncoming: ref(true),
      internalLimitReached: ref(true),
      usagePeriodEnd: ref(periodEnd),
    });
    const wrapper = mount(ReplyTopPanel, {
      props: { conversationId: 12 },
      global: {
        mocks: { $t: key => key },
        stubs: { EditorModeToggle: true, CopilotMenuBar: true },
      },
    });

    await wrapper.findAll('button')[0].trigger('click');

    expect(
      wrapper.findComponent({ name: 'CopilotMenuBar' }).props()
    ).toMatchObject({
      replySuggestionDisabledReason: 'limit',
      quotaResetDate: new Intl.DateTimeFormat('en', {
        timeZone: 'UTC',
      }).format(new Date(periodEnd)),
    });
  });
});
