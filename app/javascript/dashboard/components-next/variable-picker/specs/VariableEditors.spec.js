import { mount, flushPromises, DOMWrapper } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { Selection } from '@chatwoot/prosemirror-schema';
import VariablesAPI from 'dashboard/api/variables';
import VariablePicker from '../VariablePicker.vue';
import InsertVariableButton from 'dashboard/components-next/variable/InsertVariableButton.vue';
import Editor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AddCanned from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import EditCanned from 'dashboard/routes/dashboard/settings/canned/EditCanned.vue';
import AutomationActionInput from 'dashboard/components/widgets/AutomationActionInput.vue';
import AutomationActionCustomAttributeInput from 'dashboard/components/widgets/AutomationActionCustomAttributeInput.vue';
import LiveChatCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignForm.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MacroNode from 'dashboard/routes/dashboard/settings/macros/MacroNode.vue';
import en from 'dashboard/i18n/locale/en/variables.json';
import catalog from './catalog.json';

vi.mock('dashboard/api/variables', () => ({ default: { catalog: vi.fn() } }));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: false }),
}));
let view;
vi.mock('@chatwoot/prosemirror-schema', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    EditorView: class extends actual.EditorView {
      constructor(...args) {
        super(...args);
        view = this;
      }
    },
  };
});

const rect = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
Range.prototype.getClientRects = () => [rect];
Range.prototype.getBoundingClientRect = () => rect;
Element.prototype.scrollIntoView = () => {};
const actionTypes = [
  { key: 'send_message', label: 'Send message', inputType: 'textarea' },
];
let account = 40000;
let wrapper;
let store;
let variables;
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en },
  missingWarn: false,
  fallbackWarn: false,
});

// Mount real pickers and ProseMirror in every surface; only unrelated integrations are stubbed.
const render = (component, props = {}) => {
  wrapper = mount(component, {
    props,
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      provide: { macroActionTypes: ref(actionTypes) },
      directives: {
        dompurifyHtml: (el, binding) => {
          el.textContent = binding.value;
        },
        tooltip: () => {},
      },
      stubs: { CopilotMenuBar: true, Teleport: false },
    },
  });
  return wrapper;
};
const placeCursor = pos =>
  view.dispatch(
    view.state.tr.setSelection(Selection.near(view.state.doc.resolve(pos)))
  );
const openInsert = async () => {
  await flushPromises();
  await wrapper
    .getComponent(InsertVariableButton)
    .get('[aria-haspopup="listbox"]')
    .trigger('click');
  await flushPromises();
  return new DOMWrapper(
    [
      ...document.querySelectorAll(
        '[data-combobox-dropdown] input[type="search"]'
      ),
    ].find(
      input =>
        input.closest('[data-combobox-dropdown]').style.display !== 'none'
    )
  );
};
const choose = async label => {
  const search = await openInsert();
  await search.setValue(label);
  await search.trigger('keydown', { key: 'ArrowDown' });
  expect(document.activeElement.getAttribute('role')).toBe('option');
  document.activeElement.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })
  );
  await flushPromises();
};
beforeEach(() => {
  account += 1;
  variables = structuredClone(catalog.variables).map(variable => ({
    ...variable,
    writeContexts: variable.writable ? ['automation', 'whatsapp_flow'] : [],
  }));
  VariablesAPI.catalog.mockResolvedValue({ data: { variables } });
  store = createStore({
    getters: {
      getCurrentAccountId: () => account,
      getCurrentRole: () => 'agent',
      getUISettings: () => ({}),
      'globalConfig/get': () => ({}),
      'accounts/isRTL': () => false,
      'campaigns/getUIFlags': () => ({}),
      'inboxes/getWebsiteInboxes': () => [],
    },
  });
});
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
});

it.each([
  ['add canned', AddCanned, { responseContent: 'Hola mundo' }],
  ['edit canned', EditCanned, { edcontent: 'Hola mundo', edshortCode: 'hola' }],
  [
    'automation',
    AutomationActionInput,
    {
      modelValue: {
        action_name: 'send_message',
        action_params: ['Hola mundo'],
      },
      actionTypes,
    },
  ],
  [
    'macro',
    MacroNode,
    {
      modelValue: {
        action_name: 'send_message',
        action_params: ['Hola mundo'],
      },
    },
  ],
])(
  '%s inserts a literal hyphen attribute at the caret with arrows/Enter, repeats it and returns focus',
  async (_, component, props) => {
    render(component, props);
    await flushPromises();
    placeCursor(6);
    await choose('Nivel VIP');
    expect(view.state.doc.textContent).toBe(
      "Hola {{ contact.custom_attribute['nivel-vip'] }}mundo"
    );
    expect(view.hasFocus()).toBe(true);
    await choose('Nivel VIP');
    expect(view.state.doc.textContent.match(/nivel-vip/g)).toHaveLength(2);
    expect(view.hasFocus()).toBe(true);
    const search = await openInsert();
    await search.trigger('keydown', { key: 'Escape' });
    expect(view.hasFocus()).toBe(true);
    expect(wrapper.findComponent(Editor).exists()).toBe(true);
  }
);

it.each(['nivel.vip', 'categor\u00eda'])(
  'inserts %s exactly as provided by Rails',
  async key => {
    const attribute = variables.find(variable => variable.key === 'nivel-vip');
    attribute.key = key;
    attribute.label = key;
    attribute.expression = `{{ contact.custom_attribute['${key}'] }}`;
    render(AddCanned, { responseContent: 'Hola mundo' });
    await flushPromises();
    placeCursor(6);
    await choose(key);
    expect(view.state.doc.textContent).toBe(
      `Hola ${attribute.expression}mundo`
    );
  }
);

it('keeps the {{ trigger, filters, arrows/Enter, caret and editor focus', async () => {
  render(Editor, {
    modelValue: 'Hola mundo',
    enableVariables: true,
    enableCannedResponses: false,
  });
  placeCursor(6);
  view.dispatch(view.state.tr.insertText(' {{'));
  await flushPromises();
  const search = new DOMWrapper(document.querySelector('[role="combobox"]'));
  await search.setValue('Nivel VIP');
  await search.trigger('keydown', { key: 'ArrowDown' });
  await search.trigger('keydown', { key: 'Enter' });
  await flushPromises();
  expect(view.state.doc.textContent).toContain(
    "Hola  {{contact.custom_attribute['nivel-vip']}}"
  );
  expect(view.state.doc.textContent).toContain('mundo');
  expect(view.hasFocus()).toBe(true);
});

it('dismisses the caret picker with Escape and keeps typed text', async () => {
  render(Editor, { modelValue: 'Hola', enableVariables: true });
  view.dispatch(view.state.tr.insertText(' {{'));
  await flushPromises();
  await new DOMWrapper(document.querySelector('[role="combobox"]')).trigger(
    'keydown',
    { key: 'Escape' }
  );
  await flushPromises();
  expect(view.state.doc.textContent).toBe('Hola {{');
  expect(view.hasFocus()).toBe(true);
  expect(wrapper.find('[role="combobox"]').exists()).toBe(false);
});

it.each([
  ['add', AddCanned],
  ['edit', EditCanned],
  ['automation', AutomationActionInput],
  ['macro', MacroNode],
])(
  'preserves content through catalog failure and retry in %s',
  async (_, component) => {
    VariablesAPI.catalog.mockRejectedValueOnce(new Error('offline'));
    render(component, {
      responseContent: 'Texto guardado',
      edcontent: 'Texto guardado',
      modelValue: {
        action_name: 'send_message',
        action_params: ['Texto guardado'],
      },
      actionTypes,
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('could not');
    expect(view.state.doc.textContent).toBe('Texto guardado');
    await wrapper.get('[role="alert"] button').trigger('click');
    await flushPromises();
    expect(view.state.doc.textContent).toBe('Texto guardado');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  }
);

it('uses automation write capability for targets; calendar and formula fields are read only', async () => {
  render(AutomationActionCustomAttributeInput, {
    modelValue: { attribute_key: 'nivel-vip', value: 'No borrar' },
  });
  await flushPromises();
  const picker = wrapper.findAllComponents(VariablePicker)[0];
  expect(picker.props()).toMatchObject({
    mode: 'write',
    surface: 'automation',
    writeContext: 'automation',
  });
  await picker.get('[aria-haspopup="listbox"]').trigger('click');
  expect(document.body.textContent).toContain('Nivel VIP');
  const targetOptions = picker.getComponent(ComboBox).props('options');
  expect(
    targetOptions.every(option =>
      variables.some(
        variable =>
          variable.legacyPaths.includes(option.value) &&
          !variable.managedBy &&
          variable.writable
      )
    )
  ).toBe(true);
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  await new DOMWrapper(
    [
      ...document.querySelectorAll(
        '[data-combobox-dropdown] input[type="search"]'
      ),
    ].find(
      input =>
        input.closest('[data-combobox-dropdown]').style.display !== 'none'
    )
  ).trigger('keydown', { key: 'Escape' });
  await choose('Nivel VIP');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
    attribute_key: 'nivel-vip',
    value: "No borrar{{ contact.custom_attribute['nivel-vip'] }}",
  });
});

it('keeps an unavailable saved destination and value when the catalog fails', async () => {
  VariablesAPI.catalog.mockRejectedValueOnce(new Error('offline'));
  render(AutomationActionCustomAttributeInput, {
    modelValue: { attribute_key: 'legacy', value: '{{contact.name}}' },
  });
  await flushPromises();
  expect(wrapper.get('input[type="text"]').element.value).toBe(
    '{{contact.name}}'
  );
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});

it('requests campaign context from the shared button and emits server expressions', async () => {
  render(InsertVariableButton, { context: 'campaign' });
  await flushPromises();
  expect(VariablesAPI.catalog).toHaveBeenCalledWith(account, 'campaign');
  await choose('Nivel VIP');
  expect(wrapper.emitted('insert')[0]).toEqual([
    "{{ contact.custom_attribute['nivel-vip'] }}",
  ]);
});

it.each([
  ['add', AddCanned, { responseContent: 'Hola ' }],
  ['edit', EditCanned, { edcontent: 'Hola ' }],
])(
  'Escape only closes the caret picker inside %s canned',
  async (_, component, props) => {
    render(component, props);
    view.dispatch(view.state.tr.insertText(' {{'));
    await flushPromises();
    await new DOMWrapper(document.querySelector('[role="combobox"]')).trigger(
      'keydown',
      { key: 'Escape', code: 'Escape' }
    );
    await flushPromises();
    expect(wrapper.find('.modal-container').exists()).toBe(true);
    expect(view.hasFocus()).toBe(true);
    expect(document.querySelector('[role="combobox"]')).toBeNull();
  }
);

it('preserves content while loading and shows an empty server catalog', async () => {
  let resolve;
  VariablesAPI.catalog.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  render(AddCanned, { responseContent: 'Conservar' });
  expect(wrapper.get('[role="status"]').text()).toBe(
    en.VARIABLE_PICKER.LOADING
  );
  expect(view.state.doc.textContent).toBe('Conservar');
  resolve({ data: { variables: [] } });
  const search = await openInsert();
  expect(search.exists()).toBe(true);
  expect(document.body.textContent).toContain(en.VARIABLE_PICKER.EMPTY);
  expect(view.state.doc.textContent).toBe('Conservar');
});

it('preserves a draft when the caret catalog fails and retries without replacing the trigger', async () => {
  VariablesAPI.catalog.mockRejectedValueOnce(new Error('offline'));
  render(Editor, { modelValue: 'Hola ', enableVariables: true });
  view.dispatch(view.state.tr.insertText(' {{'));
  await flushPromises();
  const before = view.state.doc.textContent;
  await new DOMWrapper(document.querySelector('[role="alert"] button')).trigger(
    'click'
  );
  await flushPromises();
  expect(view.state.doc.textContent).toBe(before);
  expect(document.querySelector('[role="alert"]')).toBeNull();
});

it('inserts into the live campaign editor with campaign context and no global bus', async () => {
  render(LiveChatCampaignForm, {
    mode: 'edit',
    selectedCampaign: {
      title: 'Campaign',
      message: 'Hola mundo',
      inbox: { id: 1 },
      trigger_rules: { url: 'https://example.com', time_on_page: 10 },
    },
  });
  await flushPromises();
  placeCursor(6);
  await choose('Nivel VIP');
  expect(view.state.doc.textContent).toBe(
    "Hola {{ contact.custom_attribute['nivel-vip'] }}mundo"
  );
  expect(view.hasFocus()).toBe(true);
  expect(VariablesAPI.catalog).toHaveBeenCalledWith(account, 'campaign');
  expect(wrapper.vm.prepareCampaignDetails().message).toBe(
    view.state.doc.textContent
  );
});

it('keeps an existing calendar-owned destination read only without clearing the saved action', async () => {
  const managed = variables.find(variable => variable.managedBy === 'calendar');
  render(AutomationActionCustomAttributeInput, {
    modelValue: { attribute_key: managed.key, value: 'Guardado' },
  });
  await flushPromises();
  expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
  expect(wrapper.get('input[type="text"]').element.value).toBe('Guardado');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});
