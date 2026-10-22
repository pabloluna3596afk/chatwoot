import { mount } from '@vue/test-utils';
import ContactInfoRow from '../ContactInfoRow.vue';

const mountRow = props =>
  mount(ContactInfoRow, {
    props: { icon: 'mail', emoji: '✉️', title: 'Correo', ...props },
    global: {
      mocks: {
        $t: (key, params) => `${key}${params ? JSON.stringify(params) : ''}`,
      },
      directives: {
        dompurifyHtml: (el, binding) => {
          el.innerHTML = binding.value;
        },
      },
      stubs: { EmojiOrIcon: true },
    },
  });

describe('ContactInfoRow', () => {
  it('offers to add an empty editable field and hides the copy button', () => {
    const wrapper = mountRow({ value: '', editable: true, showCopy: true });
    expect(wrapper.text()).toContain('CONTACT_PANEL.ADD_FIELD');
    expect(wrapper.text()).toContain('"field":"Correo"');
    expect(wrapper.find('.i-lucide-clipboard').exists()).toBe(false);
  });

  it('keeps the plain empty text for a field nobody can edit', () => {
    const wrapper = mountRow({ value: '' });
    expect(wrapper.text()).toContain('CONTACT_PANEL.NOT_AVAILABLE');
  });

  it('starts editing when the add prompt is clicked', async () => {
    const wrapper = mountRow({ value: '', editable: true });
    await wrapper.get('button').trigger('click');
    expect(wrapper.vm.isEditing).toBe(true);
  });
});
