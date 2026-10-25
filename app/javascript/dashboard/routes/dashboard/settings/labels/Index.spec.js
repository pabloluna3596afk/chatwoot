import { shallowMount } from '@vue/test-utils';
import Index from './Index.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';
import { BaseTable } from 'dashboard/components-next/table';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('./AddLabel.vue', () => ({
  default: { name: 'AddLabel', template: '<div />' },
}));
vi.mock('./EditLabel.vue', () => ({
  default: {
    name: 'EditLabel',
    props: ['selectedResponse'],
    template: '<div />',
  },
}));
vi.mock('../components/BaseSettingsHeader.vue', () => ({
  default: {
    name: 'BaseSettingsHeader',
    emits: ['update:searchQuery'],
    template: '<div />',
  },
}));

const labels = [
  {
    id: 1,
    title: 'billing',
    description: 'Payment question',
    color: '#123456',
    show_on_sidebar: true,
  },
  {
    id: 2,
    title: 'urgent',
    description: 'Needs quick attention',
    color: '#abcdef',
    show_on_sidebar: false,
  },
];

const mountIndex = dispatch =>
  shallowMount(Index, {
    global: {
      renderStubDefaultSlot: true,
      mocks: { $t: key => key },
      plugins: [
        app => {
          app.config.globalProperties.$store = {
            dispatch,
            getters: {
              'labels/getLabels': labels,
              'labels/getUIFlags': { isFetching: false },
            },
          };
        },
      ],
      stubs: {
        SettingsLayout: {
          template:
            '<div><slot name="header"/><slot name="body"/><slot/></div>',
        },
        ListCard: {
          ...ListCard,
          template: '<div><slot name="chips"/></div>',
        },
        BaseSettingsHeader: {
          name: 'BaseSettingsHeader',
          emits: ['update:searchQuery'],
          template: '<div />',
        },
        WootModal: { template: '<div><slot/></div>' },
        WootDeleteModal: {
          name: 'WootDeleteModal',
          props: ['show', 'onConfirm'],
          template: '<button @click="onConfirm">Confirm</button>',
        },
      },
    },
  });

describe('Labels responsive list', () => {
  it('renders cards and desktop table from the same filtered records', async () => {
    const wrapper = mountIndex(vi.fn().mockResolvedValue());
    let cards = wrapper.findAllComponents(ListCard);
    expect(cards.map(card => card.props('title'))).toEqual([
      'billing',
      'urgent',
    ]);
    expect(cards[0].props('subtitle')).toBe('Payment question');
    expect(cards[0].find('[style]').element.style.backgroundColor).toBe(
      'rgb(18, 52, 86)'
    );
    expect(cards[0].props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'delete',
    ]);
    expect(cards[1].props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'delete',
    ]);
    expect(cards[0].text()).toContain('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL');
    expect(cards[1].text()).not.toContain(
      'LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL'
    );
    expect(wrapper.getComponent(BaseTable).props('items')).toEqual(labels);

    await wrapper
      .getComponent({ name: 'BaseSettingsHeader' })
      .vm.$emit('update:searchQuery', 'urgent');
    await wrapper.vm.$nextTick();
    cards = wrapper.findAllComponents(ListCard);
    expect(cards).toHaveLength(1);
    expect(cards[0].props('title')).toBe('urgent');
    expect(wrapper.getComponent(BaseTable).props('items')).toEqual([labels[1]]);
    wrapper.unmount();
  });

  it('opens the existing edit and delete confirmation flows from a card', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = mountIndex(dispatch);
    const [card] = wrapper.findAllComponents(ListCard);

    await card.vm.$emit('action', { action: 'edit' });
    expect(
      wrapper.getComponent({ name: 'EditLabel' }).props('selectedResponse')
    ).toEqual(labels[0]);

    await card.vm.$emit('action', { action: 'delete' });
    const dialog = wrapper.getComponent({ name: 'WootDeleteModal' });
    expect(dialog.props('show')).toBe(true);
    expect(dispatch).not.toHaveBeenCalledWith('labels/delete', 1);
    await dialog.trigger('click');
    expect(dispatch).toHaveBeenCalledWith('labels/delete', 1);
    wrapper.unmount();
  });
});
