import { flushPromises, shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import es from 'dashboard/i18n/locale/es/integrations.json';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import AssistantForm from './AssistantForm.vue';
import CreateAssistantDialog from './CreateAssistantDialog.vue';

const { dispatch, close } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  close: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('CreateAssistantDialog', () => {
  let wrapper;
  const details = { name: 'Support', description: 'Customer support' };

  beforeEach(() => {
    wrapper = shallowMount(CreateAssistantDialog, {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
        ],
        stubs: {
          Dialog: {
            methods: { close },
            template: '<div><slot /></div>',
          },
        },
      },
    });
  });

  afterEach(() => wrapper.unmount());

  it.each([403, 422, 500])(
    'keeps the dialog open on a %s rejection and allows retry',
    async status => {
      const message = 'Has alcanzado el límite de asistentes de tu plan.';
      dispatch.mockImplementationOnce(async () => {
        throwErrorMessage({ response: { status, data: { error: message } } });
      });
      wrapper.getComponent(AssistantForm).vm.$emit('submit', details);
      await flushPromises();

      expect(dispatch).toHaveBeenCalledWith(
        'captainAssistants/create',
        details
      );
      expect(useAlert).toHaveBeenCalledExactlyOnceWith(message);
      expect(close).not.toHaveBeenCalled();
      expect(wrapper.emitted('created')).toBeUndefined();
      expect(wrapper.emitted('close')).toBeUndefined();

      const assistant = { id: 1, ...details };
      dispatch.mockResolvedValueOnce(assistant);
      wrapper.getComponent(AssistantForm).vm.$emit('submit', details);
      await flushPromises();

      expect(wrapper.emitted('created')).toEqual([[assistant]]);
      expect(close).toHaveBeenCalledOnce();
      expect(useAlert).toHaveBeenLastCalledWith(
        es.CAPTAIN.ASSISTANTS.CREATE.SUCCESS_MESSAGE
      );
    }
  );

  it('uses the translated fallback when the store has no server message', async () => {
    dispatch.mockRejectedValueOnce(new Error(''));
    wrapper.getComponent(AssistantForm).vm.$emit('submit', details);
    await flushPromises();

    expect(useAlert).toHaveBeenCalledExactlyOnceWith(
      es.CAPTAIN.ASSISTANTS.CREATE.ERROR_MESSAGE
    );
    expect(close).not.toHaveBeenCalled();
  });

  it('preserves the edit action and closes only after it succeeds', async () => {
    await wrapper.setProps({ type: 'edit', selectedAssistant: { id: 2 } });
    dispatch.mockResolvedValueOnce({ id: 2, ...details });
    wrapper.getComponent(AssistantForm).vm.$emit('submit', details);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('captainAssistants/update', {
      id: 2,
      ...details,
    });
    expect(wrapper.emitted('created')).toBeUndefined();
    expect(close).toHaveBeenCalledOnce();
  });
});
