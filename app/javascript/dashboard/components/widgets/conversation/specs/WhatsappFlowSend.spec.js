import { mount } from '@vue/test-utils';
import WhatsappFlowSend from '../WhatsappFlowSend.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappFlows', () => ({ default: {} }));

describe('flow composer entry', () => {
  it('disables the entry without repeating the dialog window notice', () => {
    const wrapper = mount(WhatsappFlowSend, {
      props: { conversationId: 12, canReply: false },
      global: {
        stubs: { WhatsappFlowSendDialog: true },
        mocks: { $t: key => key },
      },
    });
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.get('button').attributes('title')).toBeUndefined();
    expect(wrapper.text()).not.toContain('OUTSIDE_WINDOW');
  });
});
