import { shallowMount } from '@vue/test-utils';
import Index from './Index.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';
import { BaseTable } from 'dashboard/components-next/table';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('./AddSLA.vue', () => ({
  default: { name: 'AddSLA', template: '<div />' },
}));
vi.mock('./SLAPaywallEnterprise.vue', () => ({
  default: { name: 'SLAPaywallEnterprise', template: '<div />' },
}));

const slas = [
  {
    id: 1,
    name: 'Priority support',
    description: 'High priority customers',
    only_during_business_hours: true,
    first_response_time_threshold: 300,
    next_response_time_threshold: 600,
    resolution_time_threshold: 3600,
  },
  {
    id: 2,
    name: 'Standard',
    description: 'All other customers',
    only_during_business_hours: false,
    first_response_time_threshold: 600,
    next_response_time_threshold: 1200,
    resolution_time_threshold: 7200,
  },
];

const mountIndex = (dispatch, records = slas) =>
  shallowMount(Index, {
    global: {
      renderStubDefaultSlot: true,
      stubs: {
        SettingsLayout: {
          template:
            '<div><slot name="header"/><slot name="body"/><slot/></div>',
        },
        BaseSettingsHeader: {
          name: 'BaseSettingsHeader',
          emits: ['update:searchQuery'],
          template: '<div />',
        },
        ListCard: {
          ...ListCard,
          template: '<div><slot name="chips"/></div>',
        },
        WootModal: { template: '<div><slot/></div>' },
        WootDeleteModal: {
          name: 'WootDeleteModal',
          props: ['show', 'onConfirm'],
          template: '<button @click="onConfirm">Confirm</button>',
        },
      },
      mocks: {
        $t: key => key,
        $router: { push: vi.fn() },
        $store: {
          dispatch,
          getters: {
            'globalConfig/isOnChatwootCloud': false,
            'accounts/isFeatureEnabledonAccount': () => true,
            'sla/getSLA': records,
            'sla/getUIFlags': { isFetching: false },
            getCurrentUser: { type: 'User' },
            getCurrentAccountId: 5,
          },
        },
      },
    },
  });

describe('SLA responsive list', () => {
  it('keeps the mobile cards and desktop table on the filtered SLA list', async () => {
    const wrapper = mountIndex(vi.fn().mockResolvedValue());
    let cards = wrapper.findAllComponents(ListCard);
    expect(cards.map(card => card.props('title'))).toEqual([
      'Priority support',
      'Standard',
    ]);
    expect(cards[0].props('menuItems').map(item => item.action)).toEqual([
      'delete',
    ]);
    expect(cards[0].text()).toContain('SLA.LIST.BUSINESS_HOURS_ON');
    expect(cards[0].text()).toContain('SLA.LIST.TABLE_HEADER.BUSINESS_HOURS');
    expect(cards[0].text()).toContain('SLA.FORM.FIRST_RESPONSE_TIME.LABEL');
    expect(cards[0].text()).toContain('SLA.FORM.NEXT_RESPONSE_TIME.LABEL');
    expect(cards[0].text()).toContain('SLA.FORM.RESOLUTION_TIME.LABEL');
    expect(cards[0].text()).toContain('5m');
    expect(wrapper.getComponent(BaseTable).props('items')).toEqual(slas);

    await wrapper
      .getComponent({ name: 'BaseSettingsHeader' })
      .vm.$emit('update:searchQuery', 'standard');
    await wrapper.vm.$nextTick();
    cards = wrapper.findAllComponents(ListCard);
    expect(cards).toHaveLength(1);
    expect(cards[0].props('title')).toBe('Standard');
    expect(wrapper.getComponent(BaseTable).props('items')).toEqual([slas[1]]);
    wrapper.unmount();
  });

  it('shows an em dash for empty thresholds', () => {
    const [sla] = slas;
    const wrapper = mountIndex(vi.fn().mockResolvedValue(), [
      { ...sla, first_response_time_threshold: null },
    ]);

    expect(wrapper.getComponent(ListCard).text()).toContain('—');
    wrapper.unmount();
  });

  it('opens the existing confirmation before deleting from a card', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = mountIndex(dispatch);
    const [card] = wrapper.findAllComponents(ListCard);

    await card.vm.$emit('action', { action: 'delete' });
    const dialog = wrapper.getComponent({ name: 'WootDeleteModal' });
    expect(dialog.props('show')).toBe(true);
    expect(dispatch).not.toHaveBeenCalledWith('sla/delete', 1);
    await dialog.trigger('click');
    expect(dispatch).toHaveBeenCalledWith('sla/delete', 1);
    wrapper.unmount();
  });
});
