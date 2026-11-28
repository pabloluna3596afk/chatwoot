import { shallowMount } from '@vue/test-utils';
import SearchInput from './SearchInput.vue';

describe('search shortcut', () => {
  it.each(['textarea', 'div'])('keeps / in a focused %s editor', async tag => {
    const wrapper = shallowMount(SearchInput, {
      attachTo: document.body,
      global: { mocks: { $t: key => key } },
    });
    const editor = document.createElement(tag);
    if (tag === 'div') {
      editor.contentEditable = 'true';
      editor.tabIndex = 0;
      Object.defineProperty(editor, 'isContentEditable', { value: true });
    }
    document.body.appendChild(editor);
    editor.focus();
    const event = new KeyboardEvent('keydown', {
      key: '/',
      bubbles: true,
      cancelable: true,
    });
    editor.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
    expect(document.activeElement).toBe(editor);
    editor.remove();
    wrapper.unmount();
  });

  it('focuses search with / outside editable elements', () => {
    const wrapper = shallowMount(SearchInput, {
      attachTo: document.body,
      global: { mocks: { $t: key => key } },
    });
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: '/',
        bubbles: true,
        cancelable: true,
      })
    );
    expect(document.activeElement).toBe(wrapper.get('input').element);
    wrapper.unmount();
  });
});
