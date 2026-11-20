import { flushPromises, mount } from '@vue/test-utils';
import { h, ref } from 'vue';
import Popover from '../Popover.vue';

const belowMd = ref(false);

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useBreakpoints: () => ({ smaller: () => belowMd }),
}));

describe('Popover', () => {
  let wrapper;

  const mountPopover = (props = {}) => {
    wrapper = mount(Popover, {
      props,
      slots: {
        default: '<button data-test="trigger">Open</button>',
        content: params =>
          h(
            'button',
            { 'data-test': 'panel-action', onClick: params.hide },
            'Panel'
          ),
      },
      global: {
        stubs: { teleport: true },
      },
      attachTo: document.body,
    });
    return wrapper;
  };

  const openPopover = async () => {
    await wrapper.find('[data-test="trigger"]').trigger('click');
    await flushPromises();
  };

  const desktopPopover = () => wrapper.find('.fixed[data-popover-content]');
  const mobileBackdrop = () => wrapper.find('[data-popover-backdrop]');

  beforeEach(() => {
    belowMd.value = false;
    HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function close() {
      this.removeAttribute('open');
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('opts into a mobile bottom sheet while preserving the default centered modal', async () => {
    belowMd.value = true;
    mountPopover({ mobileSheet: true });
    await openPopover();
    expect(mobileBackdrop().classes()).toContain('items-end');
    expect(wrapper.get('[data-popover-content]').classes()).toContain(
      'max-h-[82dvh]'
    );
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalled();
    wrapper.unmount();
    mountPopover();
    await openPopover();
    expect(mobileBackdrop().classes()).toContain('items-start');
    expect(wrapper.get('[data-popover-content]').classes()).not.toContain(
      'max-h-[82dvh]'
    );
  });

  it('opts into desktop focus on opening and restores the trigger on Escape', async () => {
    mountPopover({ focusContent: true });
    const trigger = wrapper.get('[data-test="trigger"]');
    trigger.element.focus();
    await openPopover();
    const action = wrapper.get('[data-test="panel-action"]');
    expect(document.activeElement).toBe(action.element);
    action.element.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    await flushPromises();
    expect(desktopPopover().exists()).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
  });

  it('restores focus when the mobile sheet is cancelled', async () => {
    belowMd.value = true;
    mountPopover({ mobileSheet: true, focusContent: true });
    // jsdom has no layout; expose the control to the shared dialog focus helper.
    const rects = vi
      .spyOn(HTMLElement.prototype, 'getClientRects')
      .mockReturnValue([{}]);
    const trigger = wrapper.get('[data-test="trigger"]');
    trigger.element.focus();
    await openPopover();
    rects.mockRestore();
    expect(document.activeElement).toBe(
      wrapper.get('[data-test="panel-action"]').element
    );
    await mobileBackdrop().trigger('cancel');
    expect(mobileBackdrop().exists()).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
    expect(wrapper.emitted('hide')).toHaveLength(1);
  });

  it('closes the native dialog when its anchor is unmounted', async () => {
    belowMd.value = true;
    mountPopover({ mobileSheet: true, focusContent: true });
    await openPopover();
    const dialog = mobileBackdrop().element;
    wrapper.unmount();
    expect(dialog.close).toHaveBeenCalledOnce();
    expect(dialog.open).toBe(false);
    expect(document.querySelector('[data-popover-content]')).toBeNull();
  });

  it('preserves the default desktop focus behavior', async () => {
    mountPopover();
    const trigger = wrapper.get('[data-test="trigger"]');
    trigger.element.focus();
    await openPopover();
    expect(document.activeElement).toBe(trigger.element);
  });

  describe('rendering and toggling', () => {
    it('renders the trigger slot and keeps the content hidden initially', () => {
      mountPopover();
      expect(wrapper.find('[data-test="trigger"]').exists()).toBe(true);
      expect(desktopPopover().exists()).toBe(false);
      expect(mobileBackdrop().exists()).toBe(false);
    });

    it('opens on trigger click and emits show', async () => {
      mountPopover();
      await openPopover();
      expect(desktopPopover().exists()).toBe(true);
      expect(wrapper.emitted('show')).toHaveLength(1);
      expect(wrapper.emitted('hide')).toBeUndefined();
    });

    it('renders the content slot inside the popover', async () => {
      mountPopover();
      await openPopover();
      expect(desktopPopover().find('[data-test="panel-action"]').exists()).toBe(
        true
      );
    });

    it('closes on a second trigger click and emits hide exactly once', async () => {
      mountPopover();
      await openPopover();
      await wrapper.find('[data-test="trigger"]').trigger('click');
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });

  describe('content slot hide', () => {
    it('closes when the slot invokes the provided hide function', async () => {
      mountPopover();
      await openPopover();
      await wrapper.find('[data-test="panel-action"]').trigger('click');
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });

  describe('exposed methods', () => {
    it('opens via show and closes via hide', async () => {
      mountPopover();
      await wrapper.vm.show();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(true);
      wrapper.vm.hide();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('show')).toHaveLength(1);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('toggles via toggle', async () => {
      mountPopover();
      await wrapper.vm.toggle();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(true);
      await wrapper.vm.toggle();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(false);
    });

    it('does not emit hide when already closed', async () => {
      mountPopover();
      wrapper.vm.hide();
      await flushPromises();
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('escape key', () => {
    const pressEscape = target =>
      (target || document).dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
      );

    it('closes on Escape while open', async () => {
      mountPopover();
      await openPopover();
      pressEscape();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('does nothing on Escape while closed', async () => {
      mountPopover();
      await flushPromises();
      pressEscape();
      await flushPromises();
      expect(wrapper.emitted('hide')).toBeUndefined();
    });

    it('closes on Escape pressed inside its own content', async () => {
      mountPopover();
      await openPopover();
      pressEscape(wrapper.find('[data-test="panel-action"]').element);
      await flushPromises();
      expect(desktopPopover().exists()).toBe(false);
    });

    it('stays open on Escape pressed inside a nested overlay', async () => {
      mountPopover();
      await openPopover();
      const overlay = document.createElement('dialog');
      overlay.className = 'ProseMirror-prompt-backdrop';
      document.body.appendChild(overlay);
      pressEscape(overlay);
      await flushPromises();
      expect(desktopPopover().exists()).toBe(true);
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('click outside', () => {
    it('closes when clicking outside', async () => {
      mountPopover();
      await openPopover();
      document.body.click();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('stays open when clicking inside the content', async () => {
      mountPopover();
      await openPopover();
      desktopPopover().element.click();
      await flushPromises();
      expect(desktopPopover().exists()).toBe(true);
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('mobile view', () => {
    it('renders a centered modal with backdrop below the md breakpoint', async () => {
      belowMd.value = true;
      mountPopover();
      await openPopover();
      expect(mobileBackdrop().exists()).toBe(true);
      expect(mobileBackdrop().find('[data-test="panel-action"]').exists()).toBe(
        true
      );
      expect(desktopPopover().exists()).toBe(false);
    });

    it('keeps the anchored popover below md when disableMobileView is set', async () => {
      belowMd.value = true;
      mountPopover({ disableMobileView: true });
      await openPopover();
      expect(mobileBackdrop().exists()).toBe(false);
      expect(desktopPopover().exists()).toBe(true);
    });
  });

  it('names the native mobile modal from its trigger and closes on cancel', async () => {
    belowMd.value = true;
    mountPopover({ describedby: 'help' });
    await openPopover();
    const modal = wrapper.find('dialog');
    expect(modal.attributes('aria-labelledby')).toBe(
      wrapper.find('span').attributes('id')
    );
    expect(modal.attributes('aria-describedby')).toBe('help');
    expect(modal.element.showModal).toHaveBeenCalledOnce();
    await modal.trigger('cancel');
    expect(wrapper.emitted('hide')).toHaveLength(1);
  });

  describe('close on scroll', () => {
    const scrollWithTriggerMovedBy = async offset => {
      await openPopover();
      wrapper.find('span').element.getBoundingClientRect = () => ({
        top: offset,
      });
      document.dispatchEvent(new Event('scroll'));
      await flushPromises();
    };

    it('closes when the trigger drifts beyond the threshold', async () => {
      mountPopover();
      await scrollWithTriggerMovedBy(100);
      expect(desktopPopover().exists()).toBe(false);
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('stays open for small drift within the threshold', async () => {
      mountPopover();
      await scrollWithTriggerMovedBy(10);
      expect(desktopPopover().exists()).toBe(true);
    });

    it('stays open when closeOnScroll is disabled', async () => {
      mountPopover({ closeOnScroll: false });
      await scrollWithTriggerMovedBy(100);
      expect(desktopPopover().exists()).toBe(true);
    });
  });
});
