import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import MoreActions from '../MoreActions.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: computed(() => ({
      id: 1,
      settings: { auto_translate: true },
    })),
  }),
}));
vi.mock('dashboard/composables/useConversationStatusActions', () => ({
  useConversationStatusActions: () => ({
    showAdditionalActions: computed(() => false),
    resolveAttributesModalRef: ref(null),
  }),
}));

const render = ({
  disabled = false,
  controlEnabled = true,
  save = vi.fn(),
} = {}) => {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({
        id: 42,
        status: 'open',
        muted: false,
        additional_attributes: { auto_translate_disabled: disabled },
      }),
      'accounts/isFeatureEnabledonAccount': () => (_, feature) =>
        feature === 'auto_translate' || controlEnabled,
    },
    actions: { setConversationAutoTranslate: save },
  });
  return mount(MoreActions, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      directives: { onClickaway: {} },
      stubs: {
        ConversationAssigneeSelector: true,
        ConversationResolveAttributesModal: true,
        ResolveAction: true,
        EmailTranscriptModal: true,
        ButtonV4: { template: '<button data-more />' },
        DropdownMenu: {
          props: ['menuItems'],
          emits: ['action'],
          template: `<div><button v-for="item in menuItems" :key="item.action"
            :data-action="item.action" @click="$emit('action', item)">{{ item.label }}</button></div>`,
        },
      },
    },
  });
};

describe('conversation translation menu', () => {
  it('hides the control when the new account feature is off', async () => {
    const wrapper = render({ controlEnabled: false });
    await wrapper.find('[data-more]').trigger('click');
    expect(wrapper.find('[data-action="auto_translate"]').exists()).toBe(false);
  });

  it.each([false, true])('saves the inverse of disabled=%s', async disabled => {
    const save = vi.fn();
    const wrapper = render({ disabled, save });
    await wrapper.find('[data-more]').trigger('click');
    const item = wrapper.find('[data-action="auto_translate"]');
    expect(item.text()).toBe(
      `CONVERSATION.HEADER.AUTO_TRANSLATE.${disabled ? 'TURN_ON' : 'TURN_OFF'}`
    );
    await item.trigger('click');
    await flushPromises();
    expect(save).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      disabled: !disabled,
    });
    expect(useAlert).toHaveBeenCalledWith(
      `CONVERSATION.HEADER.AUTO_TRANSLATE.${disabled ? 'TURNED_ON' : 'TURNED_OFF'}`
    );
  });

  it('reports a failed save without claiming success', async () => {
    const wrapper = render({
      save: vi.fn().mockRejectedValue(new Error('offline')),
    });
    await wrapper.find('[data-more]').trigger('click');
    await wrapper.find('[data-action="auto_translate"]').trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.HEADER.AUTO_TRANSLATE.UPDATE_FAILED'
    );
  });
});
