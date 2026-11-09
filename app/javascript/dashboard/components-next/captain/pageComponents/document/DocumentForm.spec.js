import { shallowMount, flushPromises } from '@vue/test-utils';
import DocumentForm from './DocumentForm.vue';
import CreateDocumentDialog from './CreateDocumentDialog.vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';

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

describe.each(['en', 'es'])('knowledge estimate (%s)', locale => {
  const mountForm = () =>
    shallowMount(DocumentForm, {
      props: { assistantId: 7 },
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
      },
    });

  it('shows the PDF pages and server units, blocks insufficient quota, and does not submit', async () => {
    mocks.dispatch.mockResolvedValueOnce({
      units: 4,
      pages: 11,
      remaining: 2,
      sufficient: false,
    });
    const wrapper = mountForm();
    await wrapper
      .findComponent({ name: 'ComboBox' })
      .vm.$emit('update:modelValue', 'pdf');
    const file = new File(['pdf'], 'help.pdf', { type: 'application/pdf' });
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [file],
    });
    await wrapper.get('input[type="file"]').trigger('change');
    await flushPromises();

    const [, data] = mocks.dispatch.mock.calls.at(-1);
    expect(data.get('pdf_file')).toBe(file);
    expect(wrapper.get('[aria-live]').text()).toContain('11');
    expect(wrapper.get('[aria-live]').text()).toContain('~4');
    expect(wrapper.get('[aria-live]').classes()).toContain('text-n-amber-11');
    expect(
      wrapper
        .findAllComponents({ name: 'Button' })
        .at(-1)
        .attributes('disabled')
    ).toBe('true');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('submit')).toBeUndefined();
    wrapper.unmount();
  });

  it('shows calculating then the URL minimum and unlimited balance', async () => {
    let resolve;
    mocks.dispatch.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = mountForm();
    wrapper.vm.state.url = 'https://example.com/help';
    await flushPromises();
    expect(wrapper.get('[aria-live]').text()).toBe(
      locale === 'en' ? 'Calculating…' : 'Calculando…'
    );
    expect(
      wrapper
        .findAllComponents({ name: 'Button' })
        .at(-1)
        .attributes('disabled')
    ).toBe('true');

    resolve({ units: 2, remaining: null, sufficient: true });
    await flushPromises();
    expect(wrapper.get('[aria-live]').text()).toContain(
      locale === 'en' ? 'at least 2' : 'al menos 2'
    );
    expect(wrapper.get('[aria-live]').text()).toContain(
      locale === 'en' ? 'unlimited' : 'ilimitadas'
    );
    expect(
      wrapper
        .findAllComponents({ name: 'Button' })
        .at(-1)
        .attributes('disabled')
    ).toBe('false');
    wrapper.unmount();
  });

  it('allows creation after estimate failure without showing an estimate', async () => {
    mocks.dispatch.mockRejectedValueOnce(new Error('server unavailable'));
    const wrapper = mountForm();
    wrapper.vm.state.url = 'https://example.com/help';
    await flushPromises();
    expect(wrapper.find('[aria-live]').exists()).toBe(false);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('submit')).toHaveLength(1);
    wrapper.unmount();
  });

  it('ignores a stale estimate after editing the URL', async () => {
    let resolve;
    mocks.dispatch.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    mocks.dispatch.mockResolvedValueOnce({
      units: 2,
      remaining: 5,
      sufficient: true,
    });
    const wrapper = mountForm();
    wrapper.vm.state.url = 'https://example.com/old';
    await flushPromises();
    wrapper.vm.state.url = 'https://example.com/new';
    await flushPromises();
    resolve({ units: 20, remaining: 0, sufficient: false });
    await flushPromises();
    expect(wrapper.get('[aria-live]').text()).not.toContain('20');
    expect(
      wrapper
        .findAllComponents({ name: 'Button' })
        .at(-1)
        .attributes('disabled')
    ).toBe('false');
    wrapper.unmount();
  });
});
