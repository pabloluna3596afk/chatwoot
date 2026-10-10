import { flushPromises, mount } from '@vue/test-utils';
import FlowPreviewDrawer from '../FlowPreviewDrawer.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';

vi.mock('dashboard/api/whatsappFlows', () => ({
  default: { show: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));

const SidePanelStub = {
  template: '<div><slot /><slot name="footer" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};
const SimulatorStub = {
  props: ['definition', 'flowName', 'attributes'],
  template: '<div data-testid="simulator">{{ flowName }}</div>',
};
const flow = { id: 4, name: 'Registro', definition: { screens: [] } };

const mountDrawer = () =>
  mount(FlowPreviewDrawer, {
    global: {
      mocks: { $t: key => key },
      stubs: { SidePanel: SidePanelStub, FlowPhoneSimulator: SimulatorStub },
    },
  });

describe('FlowPreviewDrawer', () => {
  it('loads the Flow and shows it in the interactive phone', async () => {
    WhatsappFlowsAPI.show.mockResolvedValue({ data: flow });
    const wrapper = mountDrawer();
    await wrapper.vm.open({ id: 4, name: 'Registro' });
    await flushPromises();
    expect(WhatsappFlowsAPI.show).toHaveBeenCalledWith(4);
    expect(wrapper.get('[data-testid="simulator"]').text()).toBe('Registro');
  });

  it('says so when the Flow cannot be loaded and does not draw the phone', async () => {
    WhatsappFlowsAPI.show.mockRejectedValue(new Error('x'));
    const wrapper = mountDrawer();
    await wrapper.vm.open({ id: 9, name: 'Falla' });
    await flushPromises();
    expect(wrapper.find('[data-testid="flow-preview-error"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="simulator"]').exists()).toBe(false);
  });

  it('editing goes through one button and closes the preview', async () => {
    WhatsappFlowsAPI.show.mockResolvedValue({ data: flow });
    const wrapper = mountDrawer();
    await wrapper.vm.open({ id: 4, name: 'Registro' });
    await flushPromises();
    await wrapper
      .get('[data-testid="flow-preview-edit-button"]')
      .trigger('click');
    expect(wrapper.emitted('edit')[0][0]).toEqual({ id: 4, name: 'Registro' });
  });
});
