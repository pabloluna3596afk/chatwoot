import { h } from 'vue';
import ComboBox from '../combobox/ComboBox.vue';
import { mount, shallowMount } from '@vue/test-utils';
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
  await wrapper.vm.open();
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
  wrapper.find('dialog').element.showModal = vi.fn();
  await wrapper.vm.open();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  await wrapper.setProps({ disableConfirmButton: false });
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('confirm')).toHaveLength(1);
  await wrapper.find('dialog').trigger('cancel');
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('uses ruby for alert confirmation and blue for edit confirmation', () => {
  const mountWithButtonColors = type =>
    shallowMount(Dialog, {
      props: { type, confirmButtonLabel: 'Confirm' },
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          OnClickOutside: { template: '<div><slot /></div>' },
          Button: {
            props: ['color'],
            template: '<button :data-color="color" />',
          },
        },
      },
    });

  const alertDialog = mountWithButtonColors('alert');
  const editDialog = mountWithButtonColors('edit');

  expect(alertDialog.findAll('[data-color]')[1].attributes('data-color')).toBe(
    'ruby'
  );
  expect(editDialog.findAll('[data-color]')[1].attributes('data-color')).toBe(
    'blue'
  );
  alertDialog.unmount();
  editDialog.unmount();
});

it('associates the visible title and description, including a description slot', () => {
  const wrapper = shallowMount(Dialog, {
    props: { title: 'Delete', description: 'Cannot undo' },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
      },
    },
  });
  const dialog = wrapper.find('dialog');
  expect(dialog.attributes('aria-labelledby')).toBe(
    wrapper.find('h3').attributes('id')
  );
  expect(
    wrapper.find(`[id="${dialog.attributes('aria-describedby')}"]`).text()
  ).toBe('Cannot undo');
  wrapper.unmount();
});

it('mounts fields before native initial focus and emits close only once', async () => {
  const wrapper = shallowMount(Dialog, {
    props: { ariaLabel: 'Edit' },
    slots: { default: '<input />' },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
      },
    },
  });
  const dialog = wrapper.find('dialog');
  expect(dialog.attributes('aria-label')).toBe('Edit');
  dialog.element.showModal = vi.fn(() =>
    expect(wrapper.find('input').exists()).toBe(true)
  );
  dialog.element.close = vi.fn();
  await wrapper.vm.open();
  expect(dialog.element.showModal).toHaveBeenCalledOnce();
  wrapper.vm.close();
  await dialog.trigger('close');
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('lets a teleported ComboBox consume Escape before the parent dialog', async () => {
  const wrapper = mount(Dialog, {
    props: { title: 'Edit', bodyScroll: true },
    slots: {
      default: () =>
        h(ComboBox, { teleport: true, options: [{ value: 1, label: 'One' }] }),
    },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
      },
    },
    attachTo: document.body,
  });
  const dialog = wrapper.find('dialog');
  dialog.element.showModal = vi.fn(() =>
    dialog.element.setAttribute('open', '')
  );
  dialog.element.close = vi.fn();
  await wrapper.vm.open();
  await wrapper.find('[aria-haspopup="listbox"]').trigger('click');
  const menu = dialog.element.querySelector('[data-combobox-dropdown]');
  expect(menu).not.toBeNull();
  const escape = new KeyboardEvent('keydown', {
    key: 'Escape',
    bubbles: true,
    cancelable: true,
  });
  menu.dispatchEvent(escape);
  await wrapper.vm.$nextTick();
  expect(escape.defaultPrevented).toBe(true);
  expect(
    wrapper.find('[aria-haspopup="listbox"]').attributes('aria-expanded')
  ).toBe('false');
  expect(wrapper.emitted('close')).toBeUndefined();
  expect(document.activeElement).toBe(
    wrapper.find('[aria-haspopup="listbox"]').element
  );
  wrapper.unmount();
});

it('associates a slotted description and ignores a nested cancel event', async () => {
  const wrapper = shallowMount(Dialog, {
    props: { title: 'Read only' },
    slots: { description: '<span>Details</span>' },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
      },
    },
  });
  const dialog = wrapper.find('dialog');
  dialog.element.showModal = vi.fn();
  dialog.element.close = vi.fn();
  await wrapper.vm.open();
  expect(
    wrapper.find(`[id="${dialog.attributes('aria-describedby')}"]`).text()
  ).toBe('Details');
  const child = document.createElement('dialog');
  dialog.element.appendChild(child);
  child.dispatchEvent(new Event('cancel', { bubbles: true, cancelable: true }));
  expect(wrapper.emitted('close')).toBeUndefined();
  wrapper.unmount();
});
