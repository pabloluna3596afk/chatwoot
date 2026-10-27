import { mount } from '@vue/test-utils';
import ContactsCard from './ContactsCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SaveStateButton from 'dashboard/components-next/button/SaveStateButton.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';

const { openDelete } = vi.hoisted(() => ({ openDelete: vi.fn() }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useFeaturedAttributes', () => ({
  useFeaturedAttributes: () => ({ featuredBadges: [] }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => true }),
}));

const mountCard = (props = {}) =>
  mount(ContactsCard, {
    props: { id: 9, name: 'Ana Contacto', isExpanded: true, ...props },
    global: {
      stubs: {
        CardLayout: { template: '<div><slot /><slot name="after" /></div>' },
        ContactsForm: {
          props: ['contactData'],
          data: () => ({ state: {} }),
          template: '<div data-test="contact-form" />',
        },
        Avatar: {
          template: '<div><slot name="overlay" :size="42" /></div>',
        },
        Flag: true,
        FeaturedAttributeBadges: true,
        ConfirmContactDeleteDialog: {
          props: ['selectedContact'],
          setup(_, { expose }) {
            expose({ dialogRef: { open: openDelete } });
            return {};
          },
          template: '<div data-test="delete-dialog" />',
        },
        Button: {
          props: ['label', 'icon', 'size', 'variant', 'color'],
          emits: ['click'],
          template:
            '<button :data-label="label" :data-size="size" :data-color="color" @click="$emit(\'click\')"><i :class="icon" />{{ label }}</button>',
        },
        SaveStateButton: {
          props: ['labelClean', 'size'],
          template: '<button data-test="save">{{ labelClean }}</button>',
        },
      },
    },
  });

describe('ContactsCard', () => {
  beforeEach(() => openDelete.mockClear());

  it('shows Open, Delete and Save in one compact action row and removes the old delete section', () => {
    const wrapper = mountCard();
    const actions = wrapper.findAllComponents(Button);

    expect(actions.map(button => button.attributes('data-label'))).toEqual([
      'CONTACTS_LAYOUT.CARD.OPEN',
      'CONTACTS_LAYOUT.CARD.DELETE',
    ]);
    expect(actions.every(button => button.props('size') === 'sm')).toBe(true);
    expect(wrapper.findComponent(SaveStateButton).props('labelClean')).toBe(
      'GENERAL.SAVE_STATE.SAVE'
    );
    expect(wrapper.findComponent(ConfirmContactDeleteDialog).exists()).toBe(
      true
    );
    expect(wrapper.text()).not.toContain('DELETE_CONTACT.MESSAGE');
  });

  it('opens the shared delete confirmation from the card action', async () => {
    const wrapper = mountCard();
    await wrapper
      .findAllComponents(Button)
      .find(button => button.props('label') === 'CONTACTS_LAYOUT.CARD.DELETE')
      .trigger('click');

    expect(openDelete).toHaveBeenCalledOnce();
    expect(
      wrapper.getComponent(ConfirmContactDeleteDialog).props('selectedContact')
    ).toEqual({ id: 9, name: 'Ana Contacto' });
    expect(wrapper.emitted('updateContact')).toBeUndefined();
  });

  it('opens contact details without changing delete state', async () => {
    const wrapper = mountCard();
    await wrapper
      .findAllComponents(Button)
      .find(button => button.props('label') === 'CONTACTS_LAYOUT.CARD.OPEN')
      .trigger('click');

    expect(wrapper.emitted('showContact')).toEqual([[9]]);
    expect(openDelete).not.toHaveBeenCalled();
  });

  it('shows the selection checkbox without hover and emits the checked value', async () => {
    const wrapper = mountCard({ selectable: true });
    const checkbox = wrapper.get('input[type="checkbox"]');

    expect(checkbox.attributes('aria-label')).toBe(
      'GENERAL.ACCESSIBILITY.SELECT_CONTACT'
    );
    await checkbox.setValue(true);

    expect(wrapper.emitted('select')).toEqual([[true]]);
  });
});
