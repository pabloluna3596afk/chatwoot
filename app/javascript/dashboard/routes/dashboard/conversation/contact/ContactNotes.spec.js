import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ContactNotes from './ContactNotes.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import WootEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';

const { dispatch } = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key =>
    ref(
      {
        getCurrentUser: { id: 1 },
        'contactNotes/getUIFlags': {},
        'contactNotes/getAllNotesByContactId': () => [],
      }[key]
    ),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('conversation contact notes', () => {
  it('saves more than 200 characters without truncating the note', async () => {
    const wrapper = mount(ContactNotes, {
      props: { contactId: 1 },
      global: {
        mocks: { $t: key => key },
        stubs: {
          WootEditor: true,
          'woot-modal': { template: '<div><slot /></div>' },
        },
      },
    });
    await wrapper.get('button').trigger('click');
    expect(wrapper.getComponent(Editor).props('showCharacterCount')).toBe(
      false
    );
    const content = 'A long contact note. '.repeat(20);
    wrapper.getComponent(WootEditor).vm.$emit('input', content);
    await wrapper.vm.$nextTick();
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(dispatch).toHaveBeenCalledWith('contactNotes/create', {
      content,
      contactId: 1,
    });
    wrapper.unmount();
  });
});
