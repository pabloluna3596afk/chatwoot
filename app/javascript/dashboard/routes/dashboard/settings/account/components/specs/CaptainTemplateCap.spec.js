import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CaptainTemplateCap from '../CaptainTemplateCap.vue';
import AiSettings from '../../../ai/Index.vue';

const { updateAccount, dispatch, enabled, admin } = vi.hoisted(() => ({
  updateAccount: vi.fn(),
  dispatch: vi.fn(),
  enabled: { value: true },
  admin: { value: true },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ captain_template_cap: { cap: 50, used: 3 } }),
    accountId: ref(1),
    updateAccount,
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(admin.value) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: name =>
    ref(name === 'getCurrentAccountId' ? 1 : () => enabled.value),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const render = () =>
  mount(CaptainTemplateCap, {
    global: {
      stubs: {
        SectionLayout: {
          props: ['title', 'description'],
          template: '<section>{{ title }}{{ description }}<slot/></section>',
        },
      },
    },
  });

describe('account daily utility template cap', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dispatch.mockResolvedValue({ captain_template_cap: { cap: 50, used: 3 } });
    admin.value = true;
    enabled.value = true;
  });
  it('loads usage and saves an integer account setting', async () => {
    const wrapper = render();
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('accounts/get', { accountId: 1 });
    expect(wrapper.text()).toContain('CAPTAIN_TEMPLATE_CAP.TODAY');
    await wrapper.get('input').setValue('73');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(updateAccount).toHaveBeenCalledWith({
      captain_template_daily_cap: 73,
    });
  });
  it.each(['', -1, 1.5, 10001])('rejects %s before saving', async value => {
    const wrapper = render();
    await wrapper.get('input').setValue(String(value));
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('CAPTAIN_TEMPLATE_CAP.INVALID');
    await wrapper.vm.save();
    expect(updateAccount).not.toHaveBeenCalled();
  });
  it('shows save failures inline', async () => {
    updateAccount.mockRejectedValueOnce(new Error());
    const wrapper = render();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'CAPTAIN_TEMPLATE_CAP.ERROR'
    );
  });
  it('shows a load failure when the account store returns null', async () => {
    dispatch.mockResolvedValueOnce(null);
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'CAPTAIN_TEMPLATE_CAP.ERROR'
    );
  });
  it('is hidden without Captain and for non-administrators', async () => {
    enabled.value = false;
    const wrapper = mount(AiSettings, {
      global: { stubs: { AudioTranscription: true, CaptainTemplateCap: true } },
    });
    expect(wrapper.findComponent(CaptainTemplateCap).exists()).toBe(false);
    admin.value = false;
    const agent = render();
    expect(agent.find('input').exists()).toBe(false);
  });
});
