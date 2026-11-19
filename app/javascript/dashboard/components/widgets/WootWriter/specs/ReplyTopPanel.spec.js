import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ReplyTopPanel from '../ReplyTopPanel.vue';

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    captainTasksEnabled: ref(false),
    captainEnabled: ref(false),
    isEnterprise: false,
    latestPublicMessageIsIncoming: ref(false),
    internalLimitReached: ref(false),
    usagePeriodEnd: ref(null),
  }),
}));

describe('ReplyTopPanel collapse action', () => {
  it('offers expand even without Copilot and no Hide button', async () => {
    const wrapper = mount(ReplyTopPanel, {
      global: {
        stubs: {
          NextButton: false,
          EditorModeToggle: true,
          CopilotMenuBar: true,
        },
      },
    });
    expect(
      wrapper
        .find('button[aria-label="CONVERSATION.REPLYBOX.HIDE_COMPOSER"]')
        .exists()
    ).toBe(false);
    const expand = wrapper.findAll('button').at(-1);
    expect(expand.classes()).not.toContain('max-md:hidden');
    await expand.trigger('click');
    expect(wrapper.emitted('toggleEditorSize')).toEqual([[]]);
    wrapper.unmount();
  });
});
