import { flushPromises, mount } from '@vue/test-utils';
import WhatsappFlowSendDialog from '../WhatsappFlowSendDialog.vue';

const DialogStub = {
  template: '<div><slot /><slot name="footer" /></div>',
  methods: { open() {}, close() {} },
};
const mountDialog = (canReply = true, send = vi.fn().mockResolvedValue({})) =>
  mount(WhatsappFlowSendDialog, {
    props: { flows: [{ id: 12, name: 'Customer details' }], canReply, send },
    global: { stubs: { Dialog: DialogStub }, mocks: { $t: key => key } },
  });

describe('conversation flow dialog', () => {
  it('sends exactly once with editable defaults and no client token', async () => {
    const send = vi.fn().mockResolvedValue({});
    const wrapper = mountDialog(true, send);
    await wrapper.get('[data-testid="flow-send-submit"]').trigger('click');
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith({
      whatsapp_flow_id: 12,
      header: '',
      body: 'Customer details',
      cta: 'WHATSAPP_FLOWS.SEND.OPEN',
    });
  });

  it('disables sending and explains the closed 24 hour window', async () => {
    const send = vi.fn();
    const wrapper = mountDialog(false, send);
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[data-testid="flow-send-window"]').text()).toContain(
      'WHATSAPP_FLOWS.SEND.OUTSIDE_WINDOW'
    );
    await wrapper.get('[data-testid="flow-send-submit"]').trigger('click');
    expect(send).not.toHaveBeenCalled();
  });

  it('shows server errors as received', async () => {
    const wrapper = mountDialog(
      true,
      vi.fn().mockRejectedValue({
        response: { data: { error: '131047: Meta refused' } },
      })
    );
    await wrapper.get('[data-testid="flow-send-submit"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('131047: Meta refused');
  });
});
