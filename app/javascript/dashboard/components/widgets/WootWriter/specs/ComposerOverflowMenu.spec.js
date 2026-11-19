import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ComposerOverflowMenu from '../ComposerOverflowMenu.vue';

describe('composer overflow menu', () => {
  let wrapper;
  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it.each([false, true])(
    'uses an accessible menu with phone=%s, restores focus and handles Escape',
    async phone => {
      vi.stubGlobal(
        'matchMedia',
        vi.fn(query => ({
          matches: phone && query === '(max-width: 767px)',
          media: query,
          addEventListener: vi.fn(),
          removeEventListener: vi.fn(),
        }))
      );
      HTMLDialogElement.prototype.showModal = function showModal() {
        this.setAttribute('open', '');
      };
      HTMLDialogElement.prototype.close = function close() {
        this.removeAttribute('open');
      };
      wrapper = mount(ComposerOverflowMenu, {
        attachTo: document.body,
        props: {
          items: [
            {
              key: 'signature',
              icon: 'i-ph-signature',
              label: 'Signature',
              state: 'On',
            },
          ],
        },
        global: {
          plugins: [
            createStore({ getters: { 'accounts/isRTL': () => false } }),
          ],
          stubs: { NextButton: false },
        },
      });
      const trigger = wrapper.get('[aria-haspopup="menu"]');
      expect(trigger.attributes('aria-expanded')).toBe('false');
      await trigger.trigger('click');
      await flushPromises();
      expect(trigger.attributes('aria-expanded')).toBe('true');
      const menu = document.querySelector('[role="menu"]');
      expect(Boolean(menu.closest('dialog'))).toBe(phone);
      expect(menu.querySelectorAll('[role="menuitem"]')).toHaveLength(1);
      expect(menu.textContent).toContain('On');
      menu.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
      );
      await flushPromises();
      expect(trigger.attributes('aria-expanded')).toBe('false');
      expect(document.activeElement).toBe(trigger.element);
      await trigger.trigger('click');
      await flushPromises();
      const dialog = document.querySelector('dialog');
      if (dialog) {
        dialog.click();
        await flushPromises();
        expect(trigger.attributes('aria-expanded')).toBe('false');
        await trigger.trigger('click');
        await flushPromises();
      }
      document.querySelector('[role="menuitem"]').click();
      await flushPromises();
      expect(wrapper.emitted('select')).toEqual([['signature']]);
      expect(trigger.attributes('aria-expanded')).toBe('false');
    }
  );
});
