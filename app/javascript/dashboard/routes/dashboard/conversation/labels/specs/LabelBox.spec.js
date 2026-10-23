import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LabelBox from '../LabelBox.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import AddLabelModal from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';
import Label from 'dashboard/components/ui/Label.vue';
const push = vi.hoisted(() => vi.fn());
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('conversation labels', () => {
  it('creates outside the dropdown, prefills and applies the created label, and navigates only from its name', async () => {
    const apply = vi.fn();
    const created = { id: 2, title: 'seguimiento', color: '#336699' };
    const store = createStore({
      state: { labels: [{ id: 1, title: 'vip', color: '#336699' }] },
      getters: {
        getCurrentAccountId: () => 1,
        getCurrentRole: () => 'administrator',
        getSelectedChat: () => ({ id: 9 }),
        'labels/getLabels': state => state.labels,
        'labels/getUIFlags': () => ({}),
        'conversationLabels/getUIFlags': () => ({}),
        'conversationLabels/getConversationLabels': () => () => ['vip'],
      },
      actions: {
        'labels/create': ({ state }) => {
          state.labels.push(created);
          return created;
        },
        'conversationLabels/update': (_, payload) => apply(payload),
      },
    });
    const wrapper = mount(LabelBox, {
      attachTo: document.body,
      global: {
        plugins: [store],
        components: { 'woot-label': Label },
        directives: {
          'on-clickaway': {
            mounted: el => {
              el.dataset.clickaway = 'true';
            },
          },
        },
        stubs: {
          'woot-modal': {
            props: ['show'],
            template: '<div data-testid="label-modal"><slot /></div>',
          },
          'woot-modal-header': true,
          'woot-input': true,
          'woot-color-picker': true,
          'woot-dropdown-menu': { template: '<div><slot /></div>' },
          'fluent-icon': true,
        },
      },
    });
    await wrapper.findComponent({ name: 'AddLabel' }).vm.$emit('add');
    await flushPromises();
    const dropdown = wrapper.getComponent(LabelDropdown);
    await dropdown.get('input').setValue('seguimiento');
    await dropdown.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(LabelDropdown).exists()).toBe(false);
    const modal = wrapper.getComponent(AddLabelModal);
    expect(modal.vm.title).toBe('seguimiento');
    expect(
      document
        .querySelector('[data-clickaway]')
        .contains(document.querySelector('[data-testid="label-modal"]'))
    ).toBe(false);
    await modal.vm.addLabel();
    await flushPromises();
    expect(apply).toHaveBeenCalledWith({
      conversationId: 9,
      labels: ['vip', 'seguimiento'],
    });
    expect(document.querySelector('[data-testid="label-modal"]')).toBeNull();
    const chip = wrapper.getComponent(Label);
    await chip.get('button[type="button"]').trigger('click');
    expect(push).toHaveBeenLastCalledWith({
      name: 'label_conversations',
      params: { accountId: 1, label: 'vip' },
    });
    push.mockClear();
    await chip.get('.label-close--button').trigger('click');
    expect(push).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
