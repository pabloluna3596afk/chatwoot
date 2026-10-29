import { shallowMount } from '@vue/test-utils';

import CopilotEmptyState from '../CopilotEmptyState.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountComponent = (props = {}) =>
  shallowMount(CopilotEmptyState, {
    props,
    global: {
      mocks: { $t: key => key },
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

  it('offers the prompts without requiring a Captain assistant', () => {
    const wrapper = mountComponent();

    expect(wrapper.findAll('button')).toHaveLength(4);
    expect(wrapper.text()).not.toContain(
      'CAPTAIN.ASSISTANTS.COPILOT_SETUP_REQUIRED'
    );
  });
});
