import { flushPromises, mount } from '@vue/test-utils';
import WhatsappFlowSendDialog from '../WhatsappFlowSendDialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => (key === 'WHATSAPP_FLOWS.SEND.OPEN' ? 'Open' : key),
  }),
}));

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
  it('preselects the first form and updates the default text when switching forms', async () => {
    const send = vi.fn().mockResolvedValue({});
    const wrapper = mountDialog(true, send);
    await wrapper.setProps({
      flows: [
        { id: 12, name: 'Details' },
        { id: 13, name: 'Appointment' },
      ],
    });
    expect(wrapper.get('[data-testid="flow-send-choice"]').element.value).toBe(
      '12'
    );
    await wrapper.get('[data-testid="flow-send-choice"]').setValue('13');
    await wrapper.get('[data-testid="flow-send-submit"]').trigger('click');
    expect(send).toHaveBeenCalledExactlyOnceWith({
      whatsapp_flow_id: 13,
      header: '',
      body: 'Appointment',
      cta: 'Open',
    });
  });

  it('blocks empty or overlong bubble text and button labels', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper.get('[data-testid="flow-send-body"] textarea').setValue(' ');
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('x'.repeat(1025));
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Details');
    await wrapper
      .get('[data-testid="flow-send-cta"] input')
      .setValue('x'.repeat(21));
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('keeps customization collapsed and updates the bubble live', async () => {
    const wrapper = mountDialog();
    expect(
      wrapper
        .get('[data-testid="flow-send-customize"]')
        .attributes('aria-expanded')
    ).toBe('false');
    expect(wrapper.find('[data-testid="flow-send-body"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="flow-send-preview"]').text()).toContain(
      'Customer details'
    );
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper
      .get('[data-testid="flow-send-header"] input')
      .setValue('Your appointment');
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Please complete your details');
    await wrapper
      .get('[data-testid="flow-send-cta"] input')
      .setValue('Complete');
    const preview = wrapper.get('[data-testid="flow-send-preview"]').text();
    expect(preview).toContain('Your appointment');
    expect(preview).toContain('Please complete your details');
    expect(preview).toContain('Complete');
    expect(
      wrapper
        .get('[data-testid="flow-send-header"] input')
        .attributes('maxlength')
    ).toBe('60');
    expect(
      wrapper
        .get('[data-testid="flow-send-body"] textarea')
        .attributes('maxlength')
    ).toBe('1024');
    expect(
      wrapper.get('[data-testid="flow-send-cta"] input').attributes('maxlength')
    ).toBe('20');
  });

  it('rejects emoji in the bubble button', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper
      .get('[data-testid="flow-send-cta"] input')
      .setValue('Open \u{1f600}');
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[role="alert"]').text()).toContain('button_no_emoji');
  });

  it('explains republishing when no eligible forms exist', async () => {
    const wrapper = mountDialog();
    await wrapper.setProps({ flows: [] });
    expect(wrapper.text()).toContain('WHATSAPP_FLOWS.SEND.REPUBLISH_HINT');
    expect(
      wrapper.get('[data-testid="flow-send-submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('sends exactly once with editable defaults and no client token', async () => {
    const send = vi.fn().mockResolvedValue({});
    const wrapper = mountDialog(true, send);
    await wrapper.get('[data-testid="flow-send-submit"]').trigger('click');
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith({
      whatsapp_flow_id: 12,
      header: '',
      body: 'Customer details',
      cta: 'Open',
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
