import { mount } from '@vue/test-utils';
import ContactHeader from './ContactHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ContactHeader', () => {
  it('keeps the search input and header actions at the compact size on every viewport', () => {
    const wrapper = mount(ContactHeader, {
      props: { headerTitle: 'Contacts', buttonLabel: 'New message' },
      global: {
        stubs: {
          SearchInput: {
            props: ['size'],
            template: '<input data-test="search" :data-size="size" />',
          },
          Button: {
            props: ['label', 'size'],
            template:
              '<button :data-label="label" :data-size="size">{{ label }}</button>',
          },
          ContactSortMenu: true,
          ContactColumnMenu: true,
          ContactMoreActions: true,
          ComposeConversation: {
            template: '<div><slot name="trigger" /></div>',
          },
        },
      },
    });

    expect(wrapper.getComponent(SearchInput).props('size')).toBe('sm');
    expect(
      wrapper
        .findAllComponents(Button)
        .every(button => button.props('size') === 'sm')
    ).toBe(true);
    expect(wrapper.html()).not.toContain('max-sm:min-h-11');
  });
});
