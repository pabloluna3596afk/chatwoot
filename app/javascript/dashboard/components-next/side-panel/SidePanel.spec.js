import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import SidePanel from './SidePanel.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

it('opens a named native modal with description, retains close events and delegates cancel to close', async () => {
  HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
    this.setAttribute('open', '');
  });
  HTMLDialogElement.prototype.close = vi.fn(function close() {
    this.removeAttribute('open');
  });
  const wrapper = mount(SidePanel, {
    props: { title: 'Edit', description: 'Details' },
    slots: { default: '<input />' },
    global: { stubs: { teleport: true } },
  });
  await wrapper.vm.open();
  await flushPromises();
  const dialog = wrapper.find('dialog');
  expect(dialog.element.showModal).toHaveBeenCalledOnce();
  expect(
    wrapper.find(`[id="${dialog.attributes('aria-labelledby')}"]`).text()
  ).toContain('Edit');
  expect(
    wrapper.find(`[id="${dialog.attributes('aria-describedby')}"]`).text()
  ).toBe('Details');
  await dialog.trigger('cancel');
  expect(dialog.element.close).toHaveBeenCalledOnce();
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('ignores a click that bubbles up after a button closed the panel', async () => {
  HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
    this.setAttribute('open', '');
  });
  HTMLDialogElement.prototype.close = vi.fn(function close() {
    this.removeAttribute('open');
  });
  const errorHandler = vi.fn();
  const wrapper = mount(SidePanel, {
    props: { title: 'Edit' },
    global: { stubs: { teleport: true }, config: { errorHandler } },
  });
  await wrapper.vm.open();
  const dialog = wrapper.find('dialog').element;

  wrapper.vm.close();
  await flushPromises();
  dialog.dispatchEvent(new MouseEvent('click', { bubbles: true }));

  expect(errorHandler).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('does not trap fixed dropdowns once the panel is open', async () => {
  HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
    this.setAttribute('open', '');
  });
  const wrapper = mount(SidePanel, {
    props: { title: 'Edit' },
    global: { stubs: { teleport: true, transition: true } },
  });
  await wrapper.vm.open();

  expect(wrapper.find('dialog').classes()).not.toContain(
    'will-change-transform'
  );
  wrapper.unmount();
});

it('uses the full mobile viewport only when requested', async () => {
  HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
    this.setAttribute('open', '');
  });
  const wrapper = mount(SidePanel, {
    props: { title: 'Details', fullScreenOnMobile: true },
    global: { stubs: { teleport: true } },
  });
  await wrapper.vm.open();

  expect(wrapper.find('dialog').classes()).toContain('max-md:inset-0');
  expect(wrapper.find('dialog').classes()).toContain('max-md:h-dvh');
  expect(wrapper.find('dialog').classes()).toContain('max-md:w-full');

  wrapper.unmount();
});
