import { config, mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';
import AssistantNameText from 'dashboard/components-next/AssistantNameText.vue';
import { ASSISTANT_NAME_MARKER, useAssistantName } from '../useAssistantName';

const originalPlugins = config.global.plugins;

afterEach(() => {
  config.global.plugins = originalPlugins;
});

describe.each(['es', 'en'])('useAssistantName (%s)', locale => {
  let assistant;
  let name;
  let wrapper;

  beforeEach(() => {
    assistant = ref({ name: '  Aurora  ' });
    config.global.plugins = [
      createI18n({ legacy: false, locale, messages: { en, es } }),
    ];
    wrapper = mount(
      defineComponent({
        setup() {
          name = useAssistantName(assistant);
          return () =>
            h(
              'p',
              {
                title: name.nameText('CAPTAIN.ASSISTANTS.ENVIOS.ROW_SWITCH', {
                  name: 'pedido',
                }),
                'aria-label': name.nameTextFrom('Captain'),
              },
              [h(AssistantNameText, { text: name.nameRichFrom('Captain') })]
            );
        },
      })
    );
  });

  afterEach(() => wrapper.unmount());

  it('renders a name span and plain attributes without leaking the marker', () => {
    expect(wrapper.element.textContent).toBe('Aurora');
    expect(wrapper.get('.assistant-name').attributes()).toEqual({
      class: 'assistant-name',
      title: 'Aurora',
    });
    expect(wrapper.attributes('title')).toBe(
      locale === 'es' ? 'Aurora puede usar pedido' : 'Aurora can use pedido'
    );
    expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
  });

  it.each([undefined, {}, { name: '' }, { name: '  ' }])(
    'uses Captain for a missing or empty name: %s',
    async value => {
      assistant.value = value;
      await wrapper.vm.$nextTick();
      expect(wrapper.text()).toBe('Captain');
      expect(wrapper.get('.assistant-name').attributes('title')).toBe(
        'Captain'
      );
    }
  );

  it('truncates 30 characters at 24 and keeps the full name in the span title', async () => {
    assistant.value = { name: 'a'.repeat(30) };
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe(`${'a'.repeat(24)}…`);
    expect(wrapper.get('.assistant-name').attributes('title')).toBe(
      'a'.repeat(30)
    );
    expect(wrapper.attributes('aria-label')).toBe(`${'a'.repeat(24)}…`);
    expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
  });

  it('preserves 24 characters and truncates Unicode without splitting characters', () => {
    assistant.value = { name: 'a'.repeat(24) };
    expect(name.assistantName.value).toBe('a'.repeat(24));
    assistant.value = { name: '🌟'.repeat(25) };
    expect(name.assistantName.value).toBe(`${'🌟'.repeat(24)}…`);
  });

  it('reacts to loading, editing and switching assistants', async () => {
    assistant.value = undefined;
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('Captain');
    assistant.value = { name: 'La Aurora' };
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('La Aurora');
    assistant.value.name = 'Luna';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('Luna');
  });

  it('replaces only Captain words and preserves literal replacement characters', async () => {
    expect(name.nameTextFrom('Captain, Captain. Captainship')).toBe(
      'Aurora, Aurora. Captainship'
    );
    assistant.value = { name: '$& $1 <Aurora>' };
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('$& $1 <Aurora>');
    expect(wrapper.find('aurora').exists()).toBe(false);
  });

  it('renders the exact selectable sentence for owned keys', () => {
    const sentence = mount(AssistantNameText, {
      props: {
        text: name.nameRich('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.TOGGLE'),
      },
    });
    expect(sentence.element.textContent).toBe(
      locale === 'es'
        ? 'Aurora usa los Flows y plantillas de este número'
        : 'Aurora uses the Flows and templates of this number'
    );
    expect(sentence.html()).not.toContain(ASSISTANT_NAME_MARKER);
    expect(sentence.findAll('.assistant-name')).toHaveLength(1);
    sentence.unmount();
  });

  it('does not let a sentinel in the saved name escape into the DOM', async () => {
    assistant.value = { name: `Au${ASSISTANT_NAME_MARKER}rora` };
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('Aurora');
    expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
  });
});
