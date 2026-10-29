import { mount } from '@vue/test-utils';
import CopilotThinkingGroup from '../CopilotThinkingGroup.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      ({
        'CAPTAIN.COPILOT.STEPS_SUMMARY': `${values.count} steps`,
        'CAPTAIN.COPILOT.STEPS_DURATION_minutes': `· ${values.duration} min`,
        'CAPTAIN.COPILOT.TOOLS.search_conversation': 'Searching conversations',
        'CAPTAIN.COPILOT.TOOLS.get_conversation': 'Reading conversation',
        'CAPTAIN.COPILOT.TOOLS.generic': 'Checking data',
        'CAPTAIN.COPILOT.STEPS_LABEL': 'Copilot tool steps',
        'CAPTAIN.COPILOT.STEP_ERROR': 'This step could not be completed.',
        'CAPTAIN.COPILOT.STEP_EMPTY': 'No matching results were found.',
      })[key] || key,
  }),
}));

const mountGroup = (messages, props = {}) =>
  mount(CopilotThinkingGroup, {
    props: { messages, ...props },
    global: { stubs: { Icon: true, Transition: false } },
  });

describe('CopilotThinkingGroup', () => {
  it('humanizes tool names and combines starting and completion events', () => {
    const wrapper = mountGroup([
      {
        id: 1,
        created_at: 100,
        message: {
          function_name: 'search_conversation',
          content: 'Using search_conversation',
        },
      },
      {
        id: 2,
        created_at: 220,
        message: {
          function_name: 'search_conversation',
          content: 'Completed search_conversation',
        },
      },
      {
        id: 3,
        message: {
          function_name: 'unknown_tool',
          content: 'Using unknown_tool',
        },
      },
    ]);

    expect(wrapper.text()).toContain('2 steps · 2 min');
    expect(wrapper.text()).toContain('Searching conversations');
    expect(wrapper.text()).toContain('Checking data');
    expect(wrapper.text()).not.toContain('search_conversation');
    expect(wrapper.text()).not.toContain('unknown_tool');
  });

  it('starts expanded while working and collapses after the final response', async () => {
    const wrapper = mountGroup(
      [
        {
          id: 1,
          message: { function_name: 'get_data', content: 'Using get_data' },
        },
      ],
      { defaultCollapsed: false }
    );

    expect(wrapper.find('ol').exists()).toBe(true);
    await wrapper.setProps({ defaultCollapsed: true });
    expect(wrapper.find('button').attributes('aria-expanded')).toBe('false');
  });

  it('announces and humanizes tool errors without exposing technical text', () => {
    const wrapper = mountGroup([
      {
        id: 1,
        message: {
          function_name: 'search_contacts',
          content: 'Tool failed with RuntimeError: database timeout',
        },
      },
    ]);

    expect(wrapper.find('[aria-live="polite"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('This step could not be completed.');
    expect(wrapper.text()).not.toContain('RuntimeError');
  });

  it('shows an empty-result status without exposing tool output', () => {
    const wrapper = mountGroup([
      {
        id: 1,
        message: {
          function_name: 'search_contacts',
          content: 'Completed search_contacts',
          tool_status: 'empty',
        },
      },
    ]);

    expect(wrapper.text()).toContain('No matching results were found.');
    expect(wrapper.text()).not.toContain('search_contacts');
  });
});
