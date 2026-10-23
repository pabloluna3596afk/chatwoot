import { vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContactInfo from '../ContactInfo.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import ContactMergeDialog from 'dashboard/components-next/Contacts/ContactMergeDialog.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import { ref } from 'vue';

vi.mock('dashboard/components-next/Contacts/VoiceCallButton.vue', () => ({
  default: { template: '<button />' },
}));

const { push, mergeOpen, deleteOpen } = vi.hoisted(() => ({
  push: vi.fn(),
  mergeOpen: vi.fn(),
  deleteOpen: vi.fn(),
}));
const admin = ref(true);
vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'conversation_through_inbox',
    params: { accountId: 1 },
  }),
  useRouter: () => ({ push }),
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: admin }),
}));
vi.mock('dashboard/composables/useFeaturedAttributes', () => ({
  useFeaturedAttributes: () => ({ featuredBadges: { value: [] } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const contact = {
  id: 9,
  name: 'Ana',
  phone_number: '+593999111222',
  created_at: 1700000000,
};

const mountInfo = (realDelete = false) =>
  mount(ContactInfo, {
    props: { contact },
    global: {
      plugins: [
        createStore({
          getters: {
            getSelectedChat: () => ({ id: 1, meta: { sender: {} } }),
            'contacts/getUIFlags': () => ({}),
          },
          actions: {
            'contacts/fetchContactableInbox': () => {},
            'contacts/delete': () => {},
          },
        }),
      ],
      mocks: { $t: key => key, $route: { params: { accountId: 1 } } },
      stubs: {
        Dialog: {
          props: ['confirmButtonLabel'],
          data: () => ({ opened: false }),
          methods: {
            open() {
              this.opened = true;
            },
            close() {
              this.opened = false;
            },
          },
          template: `<div v-if="opened"><button @click="$emit('confirm')">{{ confirmButtonLabel }}</button></div>`,
        },
        ContactInfoRow: true,
        ViewAllConversations: true,
        Avatar: true,
        SocialIcons: true,
        EditContact: true,
        ContactMergeDialog: {
          props: ['selectedContact'],
          template: '<div />',
          methods: { open: mergeOpen },
        },
        ConfirmContactDeleteDialog: realDelete
          ? false
          : {
              props: ['selectedContact'],
              template: '<div />',
              setup: () => ({ dialogRef: { open: deleteOpen } }),
            },
        ComposeConversation: { template: '<div><slot name="trigger" /></div>' },
        VoiceCallButton: true,
        ContactAssigneeSelector: true,
        FeaturedAttributeBadges: true,
        NextButton: { template: '<button />' },
      },
    },
  });

describe('ContactInfo header menu', () => {
  beforeEach(() => {
    admin.value = true;
  });
  it('uses compact faded controls and clear call and history labels', () => {
    const wrapper = mountInfo();
    const message = wrapper.get('[aria-label="CONTACT_PANEL.NEW_MESSAGE"]');
    expect(message.attributes()).toMatchObject({
      icon: 'i-lucide-message-circle-plus',
      slate: '',
      faded: '',
      xs: '',
    });
    expect(
      wrapper.getComponent({ name: 'ViewAllConversations' }).props('size')
    ).toBe('xs');
    expect(
      wrapper.getComponent({ name: 'VoiceCallButton' }).attributes()
    ).toMatchObject({
      size: 'xs',
      slate: '',
      faded: '',
      'tooltip-label': 'CONTACT_PANEL.CALL_FROM_PLATFORM',
    });
  });

  it('keeps merge and delete inside the more menu', async () => {
    const wrapper = mountInfo();
    expect(wrapper.getComponent(MenuPopover).props('open')).toBe(false);
    await wrapper.get('[data-testid="contact-header-menu"]').trigger('click');
    const actions = wrapper
      .getComponent(MenuPopover)
      .props('menuItems')
      .map(item => item.action);
    expect(wrapper.getComponent(MenuPopover).props('open')).toBe(true);
    expect(actions).toEqual(['profile', 'edit', 'created', 'merge', 'delete']);
  });

  it('opens the edit modal from the menu and closes it', async () => {
    const wrapper = mountInfo();
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'edit' });
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent({ name: 'EditContact' }).props('show')).toBe(
      true
    );
    expect(wrapper.getComponent(MenuPopover).props('open')).toBe(false);
  });

  it('opens merge from the menu without a visible merge button', () => {
    const wrapper = mountInfo();
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'merge' });
    expect(mergeOpen).toHaveBeenCalledOnce();
    expect(wrapper.find('.i-ph-arrows-merge').exists()).toBe(false);
    expect(
      wrapper.getComponent(ContactMergeDialog).props('selectedContact')
    ).toEqual(contact);
  });

  it('opens confirmation without deleting the contact', () => {
    const wrapper = mountInfo();
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'delete' });
    expect(deleteOpen).toHaveBeenCalledOnce();
    expect(
      wrapper.getComponent(ConfirmContactDeleteDialog).props('selectedContact')
    ).toEqual(contact);
    expect(wrapper.find('.i-ph-trash').exists()).toBe(false);
  });

  it('dispatches deletion only after the shared confirmation is accepted', async () => {
    const wrapper = mountInfo(true);
    const dispatch = vi.spyOn(wrapper.vm.$store, 'dispatch');
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'delete' });
    await wrapper.vm.$nextTick();
    expect(dispatch).not.toHaveBeenCalledWith('contacts/delete', contact.id);
    await wrapper
      .getComponent(ConfirmContactDeleteDialog)
      .get('button')
      .trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('contacts/delete', contact.id);
    expect(wrapper.emitted('panelClose')).toHaveLength(1);
    wrapper.unmount();
  });

  it('hides deletion and its dialog for agents', () => {
    admin.value = false;
    const wrapper = mountInfo();
    expect(
      wrapper
        .getComponent(MenuPopover)
        .props('menuItems')
        .map(item => item.action)
    ).not.toContain('delete');
    expect(wrapper.findComponent(ConfirmContactDeleteDialog).exists()).toBe(
      false
    );
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'delete' });
    expect(deleteOpen).not.toHaveBeenCalled();
  });

  it('leaves the removed contact after confirmation succeeds', () => {
    const wrapper = mountInfo();
    wrapper
      .getComponent(ConfirmContactDeleteDialog)
      .vm.$emit('goToContactsList');
    expect(wrapper.emitted('panelClose')).toHaveLength(1);
    expect(push).toHaveBeenCalled();
  });

  it('opens the full profile in a new tab', () => {
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    const wrapper = mountInfo();
    wrapper.getComponent(MenuPopover).vm.$emit('action', { action: 'profile' });
    expect(open).toHaveBeenCalledWith(
      '/app/accounts/1/contacts/9',
      '_blank',
      'noopener,noreferrer'
    );
    open.mockRestore();
  });
});
