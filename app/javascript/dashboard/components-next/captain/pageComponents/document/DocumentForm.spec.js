import { shallowMount, flushPromises } from '@vue/test-utils';
import DocumentForm from './DocumentForm.vue';
import CreateDocumentDialog from './CreateDocumentDialog.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn(), close: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return {
    useMapGetter: () => ref({}),
    useStore: () => ({ dispatch: mocks.dispatch }),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it.each([
  '',
  'not a URL',
  'https://',
  // eslint-disable-next-line no-script-url
  'javascript:alert(1)',
  'ftp://example.com',
])('rejects invalid URL %s and preserves the draft', async value => {
  const wrapper = shallowMount(DocumentForm, { props: { assistantId: 7 } });
  wrapper.vm.state.url = value;
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('submit')).toBeUndefined();
  expect(wrapper.vm.state.url).toBe(value);
  wrapper.vm.state.url = 'https://example.com/help?q=one';
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('submit')[0][0].get('document[external_link]')).toBe(
    'https://example.com/help?q=one'
  );
  wrapper.unmount();
});

it('does not apply URL validation to PDF uploads', async () => {
  const wrapper = shallowMount(DocumentForm, { props: { assistantId: 7 } });
  wrapper.vm.state.documentType = 'pdf';
  wrapper.vm.state.url = 'invalid';
  wrapper.vm.state.pdfFile = new File(['pdf'], 'help.pdf', {
    type: 'application/pdf',
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('submit')[0][0].has('document[external_link]')).toBe(
    false
  );
  wrapper.unmount();
});

it('shows the store Error message and keeps the document form open for correction', async () => {
  mocks.dispatch.mockRejectedValueOnce(
    new Error('External link already exists')
  );
  const wrapper = shallowMount(CreateDocumentDialog, {
    props: { assistantId: 7 },
    global: {
      stubs: {
        Dialog: {
          methods: { close: mocks.close },
          template: '<div><slot /></div>',
        },
      },
    },
  });
  wrapper.findComponent(DocumentForm).vm.$emit('submit', new FormData());
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'External link already exists'
  );
  expect(mocks.close).not.toHaveBeenCalled();
  expect(wrapper.emitted('createSuccess')).toBeUndefined();
  wrapper.unmount();
});
