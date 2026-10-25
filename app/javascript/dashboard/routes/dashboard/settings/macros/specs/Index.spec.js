import { shallowMount } from '@vue/test-utils';
import { vi } from 'vitest';
import { createMemoryHistory, createRouter } from 'vue-router';
import Index from '../Index.vue';
import MacroListItem from '../MacroListItem.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';

const { macros, dispatch } = vi.hoisted(() => ({
  macros: [
    {
      id: 1,
      name: 'Close conversation',
      folder: 'Support',
      visibility: 'global',
      created_by_id: 3,
      created_by: { available_name: 'Maya Chen', email: 'maya@example.com' },
      actions: [],
    },
    {
      id: 2,
      name: 'Personal reply',
      folder: '',
      visibility: 'personal',
      created_by_id: 7,
      created_by: { available_name: 'Alex Rivera', email: 'alex@example.com' },
      actions: [],
    },
  ],
  dispatch: vi.fn().mockResolvedValue(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values?.name ? `${key}: ${values.name}` : key),
  }),
}));
vi.mock('dashboard/helper/AnalyticsHelper/index', () => ({ default: {} }));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: {},
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({
    'macros/getMacros': { value: macros },
    'macros/getUIFlags': { value: { isFetching: false } },
  }),
  useStore: () => ({ dispatch }),
  useMapGetter: () => ({ value: { id: 7 } }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));
vi.mock('dashboard/components-next/ListCard/ListCard.vue', () => ({
  default: {
    name: 'ListCard',
    props: ['title', 'subtitle', 'menuItems'],
    emits: ['action'],
    template: '<div><slot name="avatar"/><slot name="chips"/></div>',
  },
}));
vi.mock('dashboard/components-next/ListCard/InfoChip.vue', () => ({
  default: { name: 'InfoChip', template: '<span><slot/></span>' },
}));
vi.mock('dashboard/components-next/avatar/Avatar.vue', () => ({
  default: { name: 'Avatar', template: '<div />' },
}));
vi.mock('dashboard/components-next/button/Button.vue', () => ({
  default: { name: 'Button', template: '<button />' },
}));
vi.mock('../SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div><slot name="header"/><slot name="body"/></div>',
  },
}));
vi.mock('../components/SettingsFilterDropdown.vue', () => ({
  default: {
    name: 'SettingsFilterDropdown',
    props: ['modelValue', 'options'],
    emits: ['update:modelValue'],
    template: '<div />',
  },
}));
vi.mock('../components/BaseSettingsHeader.vue', () => ({
  default: {
    name: 'BaseSettingsHeader',
    emits: ['update:searchQuery'],
    template: '<div><slot name="tabs"/><slot name="count"/></div>',
  },
}));

const mountIndex = () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: { template: '<div />' } },
      {
        name: 'macros_edit',
        path: '/macros/:macroId/edit',
        component: { template: '<div />' },
      },
    ],
  });
  vi.spyOn(router, 'push');
  const wrapper = shallowMount(Index, {
    global: {
      renderStubDefaultSlot: true,
      mocks: { $t: key => key },
      plugins: [router],
      stubs: {
        MacroListItem: false,
        ListCard: false,
        SettingsLayout: {
          template: '<div><slot name="header"/><slot name="body"/></div>',
        },
        WootDeleteModal: {
          name: 'WootDeleteModal',
          props: ['show', 'onConfirm'],
          template: '<button @click="onConfirm">Confirm</button>',
        },
      },
    },
  });
  return { wrapper, router };
};

describe('Macros responsive list', () => {
  beforeEach(() => {
    dispatch.mockClear();
  });

  it('uses ListCard for sorted macros and retains folder filtering', async () => {
    const { wrapper } = mountIndex();
    let cards = wrapper.findAllComponents(ListCard);

    expect(cards.map(card => card.props('title'))).toEqual([
      'Close conversation',
      'Personal reply',
    ]);
    expect(cards[0].props('subtitle')).toBe('Maya Chen');
    expect(cards[0].props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'duplicate',
    ]);
    expect(cards[1].props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'duplicate',
      'delete',
    ]);
    expect(wrapper.text()).toContain('MACROS.EDITOR.VISIBILITY.GLOBAL.LABEL');
    expect(wrapper.text()).toContain('Support');

    await wrapper
      .getComponent({ name: 'BaseSettingsHeader' })
      .vm.$emit('update:searchQuery', 'Close');
    cards = wrapper.findAllComponents(ListCard);
    expect(cards.map(card => card.props('title'))).toEqual([
      'Close conversation',
    ]);
    wrapper.unmount();
  });

  it('routes edit and keeps delete and duplicate actions on their existing flows', async () => {
    const { wrapper, router } = mountIndex();
    const [globalCard, personalCard] = wrapper.findAllComponents(ListCard);

    await globalCard.vm.$emit('action', { action: 'edit' });
    expect(router.push).toHaveBeenCalledWith({
      name: 'macros_edit',
      params: { macroId: 1 },
    });

    await personalCard.vm.$emit('action', { action: 'duplicate' });
    expect(dispatch).toHaveBeenCalledWith(
      'macros/create',
      expect.objectContaining({
        name: 'Personal reply (copy)',
        visibility: 'personal',
        folder: '',
      })
    );

    await personalCard.vm.$emit('action', { action: 'delete' });
    expect(
      wrapper.getComponent({ name: 'WootDeleteModal' }).props('show')
    ).toBe(true);
    expect(dispatch).not.toHaveBeenCalledWith('macros/delete', 2);
    await wrapper.getComponent({ name: 'WootDeleteModal' }).trigger('click');
    expect(dispatch).toHaveBeenCalledWith('macros/delete', 2);
    wrapper.unmount();
  });
});

describe('MacroListItem permissions', () => {
  it('allows view and duplicate but hides delete for public macros without permission', () => {
    const wrapper = shallowMount(MacroListItem, {
      props: {
        macro: macros[0],
        canManagePublicMacros: false,
      },
      global: {
        mocks: { $t: key => key },
        stubs: {
          ListCard: false,
          Avatar: true,
          InfoChip: { template: '<span><slot/></span>' },
        },
      },
    });

    const card = wrapper.getComponent(ListCard);
    expect(card.props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'duplicate',
    ]);
    expect(card.props('menuItems')[0].label).toBe('MACROS.VIEW.TOOLTIP');
    wrapper.unmount();
  });

  it('shows duplication progress and disables duplicate while creating the copy', () => {
    const wrapper = shallowMount(MacroListItem, {
      props: {
        macro: macros[1],
        isDuplicating: true,
      },
      global: {
        mocks: { $t: key => key },
        stubs: {
          ListCard: false,
          Avatar: true,
          InfoChip: { template: '<span><slot/></span>' },
        },
      },
    });

    const card = wrapper.getComponent(ListCard);
    const duplicateAction = card
      .props('menuItems')
      .find(item => item.action === 'duplicate');
    expect(duplicateAction.disabled).toBe(true);
    expect(duplicateAction.label).toBe('MACROS.DUPLICATE.PROGRESS');
    expect(wrapper.text()).toContain('MACROS.DUPLICATE.PROGRESS');
    wrapper.unmount();
  });
});
