import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import AssistantSwitcher from './AssistantSwitcher.vue';
import PortalSwitcher from 'dashboard/components-next/HelpCenter/PortalSwitcher/PortalSwitcher.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn(), push: vi.fn() }));
const assistants = [
  { id: 1, name: 'Current assistant' },
  { id: 2, name: 'Another assistant with a long name' },
];
const portals = [
  { slug: 'current', name: 'Current portal', meta: { default_locale: 'en' } },
  {
    slug: 'other',
    name: 'Another portal',
    custom_domain: 'help.example.com',
    meta: { default_locale: 'es' },
  },
];
vi.mock('dashboard/composables/store.js', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: key => ref(key.startsWith('captain') ? assistants : portals),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'captain_assistants_scenarios_index',
    params: { accountId: '5', assistantId: '1', portalSlug: 'current' },
  }),
  useRouter: () => ({ push: mocks.push }),
}));

beforeEach(() => {
  mocks.dispatch.mockResolvedValue({});
  mocks.push.mockResolvedValue({});
});

describe.each([
  [AssistantSwitcher, 'Another assistant', 'createAssistant'],
  [PortalSwitcher, 'Another portal', 'createPortal'],
])('responsive switcher', (Component, query, createEvent) => {
  it('searches, exposes selected state and supports Escape with focus return', async () => {
    const wrapper = mount(Component, { attachTo: document.body });
    try {
      const trigger = wrapper.get('button');
      trigger.element.focus();
      await trigger.trigger('click');
      const menu = wrapper.getComponent(DropdownMenu);
      expect(menu.element.parentElement).toBe(document.body);
      expect(menu.props('menuItems')[0].isSelected).toBe(true);
      await menu.get('input').setValue(query);
      expect(
        menu.findAll('button').filter(button => button.text().includes(query))
      ).toHaveLength(1);
      await menu.trigger('keydown', { key: 'Escape' });
      await flushPromises();
      expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
      expect(document.activeElement).toBe(trigger.element);
      expect(wrapper.getComponent(MenuPopover).props('panelClass')).toContain(
        'max-w-[calc(100vw-2rem)]'
      );
    } finally {
      wrapper.unmount();
    }
  });

  it('keeps creation reachable independently of filtered results', async () => {
    const wrapper = mount(Component);
    try {
      await wrapper.get('button').trigger('click');
      const menu = wrapper.getComponent(DropdownMenu);
      await menu.get('input').setValue('no matching record');
      await menu.findAll('button').at(-1).trigger('click');
      expect(wrapper.emitted(createEvent)).toHaveLength(1);
      expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    } finally {
      wrapper.unmount();
    }
  });
});

it('retains the Captain account, route, numeric ID and prefetch contract', async () => {
  const wrapper = mount(AssistantSwitcher);
  try {
    await wrapper.vm.handleAssistantChange(assistants[0]);
    expect(mocks.push).not.toHaveBeenCalled();
    await wrapper.vm.handleAssistantChange(assistants[1]);
    expect(mocks.dispatch).toHaveBeenCalledWith('captainScenarios/get', {
      assistantId: 2,
    });
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'captain_assistants_scenarios_index',
      params: { accountId: '5', assistantId: 2 },
    });
  } finally {
    wrapper.unmount();
  }
});

it('retains portal locale and loading dispatches', async () => {
  const wrapper = mount(PortalSwitcher);
  try {
    await wrapper.vm.handlePortalChange(portals[1]);
    expect(mocks.dispatch).toHaveBeenCalledWith('portals/show', {
      portalSlug: 'other',
      locale: 'es',
    });
    expect(mocks.dispatch).toHaveBeenCalledWith('categories/index', {
      portalSlug: 'other',
      locale: 'es',
    });
    expect(mocks.dispatch).toHaveBeenLastCalledWith(
      'portals/switchPortal',
      false
    );
    expect(mocks.push).toHaveBeenCalledWith(
      expect.objectContaining({ params: { portalSlug: 'other', locale: 'es' } })
    );
  } finally {
    wrapper.unmount();
  }
});
