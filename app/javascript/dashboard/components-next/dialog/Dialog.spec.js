import { shallowMount } from '@vue/test-utils';
import Dialog from './Dialog.vue';

vi.mock('dashboard/components-next/TeleportWithDirection.vue', () => ({
  default: { template: '<div><slot /></div>' },
}));
const mountDialog = props =>
  shallowMount(Dialog, {
    props,
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
      },
    },
  });

it('blocks user dismissal and repeated form submission while loading, permits success close', async () => {
  const wrapper = mountDialog({ isLoading: true });
  const native = wrapper.find('dialog').element;
  native.showModal = vi.fn();
  native.close = vi.fn();
  wrapper.vm.open();
  await wrapper.find('form').trigger('submit');
  await wrapper.find('dialog').trigger('cancel');
  wrapper.vm.handleClickOutside({ target: document.body });
  expect(wrapper.emitted('confirm')).toBeUndefined();
  expect(wrapper.emitted('close')).toBeUndefined();
  expect(native.close).not.toHaveBeenCalled();
  wrapper.vm.close();
  expect(native.close).toHaveBeenCalledOnce();
  wrapper.unmount();
});

it('honors disabled confirmation on submit and restores cancel after loading', async () => {
  const wrapper = mountDialog({ disableConfirmButton: true });
  wrapper.find('dialog').element.close = vi.fn();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  await wrapper.setProps({ disableConfirmButton: false });
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('confirm')).toHaveLength(1);
  await wrapper.find('dialog').trigger('cancel');
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});
