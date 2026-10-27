import { mount, flushPromises } from '@vue/test-utils';
import ConfirmContactDeleteDialog from './ConfirmContactDeleteDialog.vue';

const { dispatch, close, alert } = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue(),
  close: vi.fn(),
  alert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: {} }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: alert }));

describe('ConfirmContactDeleteDialog', () => {
  const mountDialog = () =>
    mount(ConfirmContactDeleteDialog, {
      props: { selectedContact: { id: 9, name: 'Ana' } },
      global: {
        stubs: {
          Dialog: {
            props: ['title', 'description', 'confirmButtonLabel'],
            emits: ['confirm', 'cancel'],
            setup(_, { expose }) {
              expose({ open: vi.fn(), close });
              return {};
            },
            template: `
              <div>
                <button data-test="cancel" @click="$emit('cancel')">Cancel</button>
                <button data-test="confirm" @click="$emit('confirm')">{{ confirmButtonLabel }}</button>
              </div>
            `,
          },
        },
      },
    });

  beforeEach(() => {
    dispatch.mockClear();
    close.mockClear();
    alert.mockClear();
  });

  it('does not delete when the confirmation is cancelled', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-test="cancel"]').trigger('click');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalled();
    expect(wrapper.emitted('goToContactsList')).toBeUndefined();
  });

  it('deletes only after confirmation and returns to the contacts list', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/delete', 9);
    expect(wrapper.emitted('goToContactsList')).toHaveLength(1);
    expect(close).toHaveBeenCalledOnce();
  });
});
