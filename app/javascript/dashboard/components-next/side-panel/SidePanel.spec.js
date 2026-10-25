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
