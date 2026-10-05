import { flushPromises, mount } from '@vue/test-utils';
import FlowPage from '../FlowPage.vue';
import FlowBuilderPage from '../FlowBuilderPage.vue';
import FlowStart from '../FlowStart.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';

const { route, push, replace } = vi.hoisted(() => ({
  route: { name: 'settings_flow_new', params: {}, fullPath: '/' },
  push: vi.fn(),
  replace: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push, replace }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: {
    show: vi.fn(),
    validate: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
  },
}));

const savedFlow = {
  id: 5,
  name: 'Guardado',
  categories: [],
  definition: {
    schema_version: 1,
    screens: [
      {
        title: 'Uno',
        button: 'Enviar',
        blocks: [{ type: 'heading', text: 'Hola' }],
      },
    ],
  },
};

const mountPage = async routeState => {
  Object.assign(route, routeState);
  const wrapper = mount(FlowPage, {
    global: { mocks: { $t: key => key }, stubs: { Dialog: true } },
  });
  await flushPromises();
  return wrapper;
};

const list = { name: 'settings_templates', query: { tab: 'flows' } };

describe('FlowPage', () => {
  beforeEach(() => {
    push.mockReset();
    replace.mockReset();
    Object.values(WhatsappFlowsAPI).forEach(fn => fn.mockReset());
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [], flow_json: {} },
    });
  });

  it('shows the start step on /flows/new and turns into the builder in the same page', async () => {
    const wrapper = await mountPage({ name: 'settings_flow_new', params: {} });
    expect(wrapper.findComponent(FlowStart).exists()).toBe(true);
    expect(wrapper.findComponent(FlowBuilderPage).exists()).toBe(false);

    wrapper.findComponent(FlowStart).vm.$emit('create', {
      id: null,
      name: 'Nuevo',
      categories: [],
      definition: savedFlow.definition,
    });
    await flushPromises();

    expect(wrapper.findComponent(FlowStart).exists()).toBe(false);
    expect(wrapper.findComponent(FlowBuilderPage).props('flow').name).toBe(
      'Nuevo'
    );
    expect(push).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
  });

  it('shows the start step again on a reload of /flows/new', async () => {
    const wrapper = await mountPage({ name: 'settings_flow_new', params: {} });
    expect(wrapper.findComponent(FlowStart).exists()).toBe(true);
    expect(wrapper.findComponent(FlowBuilderPage).exists()).toBe(false);
  });

  it('cancelling the start screen goes back to the Flows tab', async () => {
    const wrapper = await mountPage({ name: 'settings_flow_new', params: {} });

    wrapper.findComponent(FlowStart).vm.$emit('cancel');

    expect(push).toHaveBeenCalledWith(list);
  });

  it('loads a saved flow into the builder', async () => {
    WhatsappFlowsAPI.show.mockResolvedValue({ data: savedFlow });

    const wrapper = await mountPage({
      name: 'settings_flow_edit',
      params: { flowId: '5' },
    });

    expect(WhatsappFlowsAPI.show).toHaveBeenCalledWith('5');
    expect(wrapper.findComponent(FlowBuilderPage).props('flow').name).toBe(
      'Guardado'
    );
  });

  it('goes back to the Flows tab of the list from the builder', async () => {
    WhatsappFlowsAPI.show.mockResolvedValue({ data: savedFlow });
    const wrapper = await mountPage({
      name: 'settings_flow_edit',
      params: { flowId: '5' },
    });

    wrapper.findComponent(FlowBuilderPage).vm.$emit('back');

    expect(push).toHaveBeenCalledWith(list);
  });

  it('gives a new flow its own address the first time it is saved', async () => {
    const wrapper = await mountPage({ name: 'settings_flow_new', params: {} });
    wrapper.findComponent(FlowStart).vm.$emit('create', {
      ...savedFlow,
      id: null,
    });
    await flushPromises();

    wrapper.findComponent(FlowBuilderPage).vm.$emit('saved', { id: 8 });

    expect(replace).toHaveBeenCalledWith({
      name: 'settings_flow_edit',
      params: { flowId: 8 },
    });
  });

  it('goes back to the list when the flow cannot be loaded', async () => {
    WhatsappFlowsAPI.show.mockRejectedValue(new Error('404'));

    await mountPage({ name: 'settings_flow_edit', params: { flowId: '99' } });

    expect(push).toHaveBeenCalledWith(list);
  });
});
