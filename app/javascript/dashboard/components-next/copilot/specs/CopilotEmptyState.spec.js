import { shallowMount } from '@vue/test-utils';

import CopilotEmptyState from '../CopilotEmptyState.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/app/accounts/1/conversations/1',
    params: { accountId: '1' },
  }),
}));

const mountComponent = (props = {}) =>
  shallowMount(CopilotEmptyState, {
    props: { hasAssistants: true, ...props },
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
      },
    },
  });

describe('CopilotEmptyState', () => {
  it('offers the four working Copilot prompts', () => {
    const wrapper = mountComponent();
    const prompts = wrapper.findAll('button');

    expect(prompts).toHaveLength(4);
    expect(wrapper.text()).toContain(
      'CAPTAIN.COPILOT.PROMPTS.OPEN_BY_AGENT.LABEL'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.COPILOT.PROMPTS.VIP_CONTACTS.LABEL'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.COPILOT.PROMPTS.PROPOSE_URGENT.LABEL'
    );
  });

  it('sends the current conversation summary prompt', async () => {
    const wrapper = mountComponent();
    const prompts = wrapper.findAll('button');

    await prompts[1].trigger('click');

    expect(wrapper.emitted('useSuggestion')[0][0]).toBe(
      'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT'
    );
  });

  it('explains the assistant requirement and links to assistant creation', () => {
    const wrapper = mountComponent({ hasAssistants: false });

    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.COPILOT_SETUP_REQUIRED'
    );
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.CREATE_FOR_COPILOT');
    expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
      name: 'captain_assistants_create_index',
      params: { accountId: '1' },
    });
  });
});
