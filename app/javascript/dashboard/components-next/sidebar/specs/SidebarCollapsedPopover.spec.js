import { h, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import SidebarCollapsedPopover from '../SidebarCollapsedPopover.vue';
import TemplatesSidebarLeaf from '../TemplatesSidebarLeaf.vue';
const sync = vi.hoisted(() => vi.fn());
vi.mock('../provider', () => ({
  useSidebarContext: () => ({ isAllowed: () => true, sidebarWidth: ref(64) }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('dashboard/composables/useWhatsAppTemplateSync', () => ({
  useWhatsAppTemplateSync: () => ({
    isSyncing: ref(false),
    canSync: ref(true),
    syncTemplates: sync,
  }),
}));
describe('template sync sidebar', () => {
  it('renders one refresh action with the leaf both collapsed and expanded', async () => {
    const child = {
      name: 'templates',
      label: 'Plantillas y Flows',
      to: '/templates',
      showTemplateSync: true,
      component: () => h(TemplatesSidebarLeaf, { label: 'Plantillas y Flows' }),
    };
    const collapsed = mount(SidebarCollapsedPopover, {
      props: { label: 'Ajustes', children: [child] },
      global: {
        stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
      },
    });
    await flushPromises();
    expect(collapsed.findAll('.i-lucide-refresh-cw')).toHaveLength(1);
    await collapsed
      .get('[aria-label="WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES"]')
      .trigger('click');
    expect(sync).toHaveBeenCalledTimes(1);
    const expanded = mount(TemplatesSidebarLeaf, {
      props: { label: child.label },
    });
    expect(expanded.findAll('.i-lucide-refresh-cw')).toHaveLength(1);
    collapsed.unmount();
    expanded.unmount();
  });
});
