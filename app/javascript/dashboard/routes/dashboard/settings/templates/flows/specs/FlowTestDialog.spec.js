import { flushPromises, mount } from '@vue/test-utils';
import FlowTestDialog from '../FlowTestDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const DialogStub = {
  name: 'Dialog',
  props: ['title'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template:
    '<div v-if="isOpen" :data-title="title"><slot /><slot name="footer" /></div>',
};

const InputStub = {
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template:
    '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
};

const wabas = [
  {
    waba_id: '111',
    channel_id: 7,
    phone_number: '+593990000001',
    inbox_name: 'Ventas',
  },
  { waba_id: '222', channel_id: 8, phone_number: '+593990000002' },
];

const mountDialog = (send = vi.fn().mockResolvedValue({}), list = wabas) => {
  const wrapper = mount(FlowTestDialog, {
    props: { wabas: list, send },
    global: {
      mocks: { $t: (key, args) => (args ? `${key} ${args.number}` : key) },
      stubs: { Dialog: DialogStub, Input: InputStub },
    },
  });
  wrapper.vm.open();
  return { wrapper, send };
};

const type = (wrapper, value) =>
  wrapper.get('[data-testid="flow-test-number"]').setValue(value);

describe('FlowTestDialog', () => {
  it('lists the Cloud channels and warns about the 24 h window', async () => {
    const { wrapper } = mountDialog();
    await wrapper.vm.$nextTick();

    const options = wrapper
      .findComponent('[data-testid="flow-test-channel"]')
      .props('options');
    expect(options).toHaveLength(2);
    // the inbox and its number, never the WABA id
    expect(options[0].label).toBe('Ventas · +593990000001');
    expect(options[1].label).toBe('+593990000002');
    expect(wrapper.text()).not.toContain('WABA');
    expect(wrapper.get('[data-testid="flow-test-window"]').text()).toContain(
      'WHATSAPP_FLOWS.META.TEST_WINDOW'
    );
  });

  it('cannot send without a number', async () => {
    const { wrapper } = mountDialog();
    await wrapper.vm.$nextTick();

    expect(
      wrapper.get('[data-testid="flow-test-send"]').attributes('disabled')
    ).toBeDefined();
    await type(wrapper, '+593 99 123');
    expect(
      wrapper.get('[data-testid="flow-test-send"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('sends the number and the chosen channel', async () => {
    const { wrapper, send } = mountDialog();
    await wrapper.vm.$nextTick();

    wrapper
      .findComponent('[data-testid="flow-test-channel"]')
      .vm.$emit('update:modelValue', 8);
    await type(wrapper, ' 593991234567 ');
    await wrapper.get('[data-testid="flow-test-send"]').trigger('click');
    await flushPromises();

    expect(send).toHaveBeenCalledWith({
      channelId: 8,
      phoneNumber: '593991234567',
    });
  });

  it('starts on the first channel', async () => {
    const { wrapper, send } = mountDialog();
    await wrapper.vm.$nextTick();

    await type(wrapper, '593991234567');
    await wrapper.get('[data-testid="flow-test-send"]').trigger('click');

    expect(send).toHaveBeenCalledWith({
      channelId: 7,
      phoneNumber: '593991234567',
    });
  });

  it('says it was sent, to which number', async () => {
    const { wrapper } = mountDialog();
    await wrapper.vm.$nextTick();

    await type(wrapper, '593991234567');
    await wrapper.get('[data-testid="flow-test-send"]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-testid="flow-test-success"]').text()).toContain(
      '593991234567'
    );
    expect(wrapper.find('[data-testid="flow-test-error"]').exists()).toBe(
      false
    );
  });

  it("shows Meta's reason when it cannot send", async () => {
    const send = vi.fn().mockRejectedValue({
      response: { data: { success: false, error: 'Re-engagement message' } },
    });
    const { wrapper } = mountDialog(send);
    await wrapper.vm.$nextTick();

    await type(wrapper, '593991234567');
    await wrapper.get('[data-testid="flow-test-send"]').trigger('click');
    await flushPromises();

    const error = wrapper.get('[data-testid="flow-test-error"]').text();
    expect(error).toContain('WHATSAPP_FLOWS.META.TEST_FAILED');
    expect(error).toContain('Re-engagement message');
    expect(wrapper.find('[data-testid="flow-test-success"]').exists()).toBe(
      false
    );
  });

  it('forgets the last result when it opens again', async () => {
    const { wrapper } = mountDialog();
    await wrapper.vm.$nextTick();
    await type(wrapper, '593991234567');
    await wrapper.get('[data-testid="flow-test-send"]').trigger('click');
    await flushPromises();

    wrapper.vm.open();
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-testid="flow-test-success"]').exists()).toBe(
      false
    );
  });
});
