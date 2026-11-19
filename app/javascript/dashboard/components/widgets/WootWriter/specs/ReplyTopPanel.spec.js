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
  it('offers Hide and expand even without Copilot, with desktop-only Hide', async () => {
    const wrapper = mount(ReplyTopPanel, {
      global: {
        stubs: {
          NextButton: false,
          EditorModeToggle: true,
          CopilotMenuBar: true,
        },
      },
    });
    const hide = wrapper.get(
      'button[aria-label="CONVERSATION.REPLYBOX.HIDE_COMPOSER"]'
    );
    expect(hide.classes()).toContain('max-md:hidden');
    await hide.trigger('click');
    expect(wrapper.emitted('collapse')).toEqual([[]]);
    const expand = wrapper.findAll('button').at(-1);
    expect(expand.classes()).not.toContain('max-md:hidden');
    await expand.trigger('click');
    expect(wrapper.emitted('toggleEditorSize')).toEqual([[]]);
    wrapper.unmount();
  });
});
