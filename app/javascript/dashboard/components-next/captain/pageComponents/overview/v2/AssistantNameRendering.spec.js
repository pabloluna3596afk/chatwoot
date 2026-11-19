import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { defineComponent, h } from 'vue';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';
import {
  ASSISTANT_NAME_MARKER,
  useAssistantName,
} from 'dashboard/composables/useAssistantName';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import CsatCard from './CsatCard.vue';

const originalPlugins = config.global.plugins;
afterEach(() => {
  config.global.plugins = originalPlugins;
});

describe.each(['es', 'en'])(
  'assistant name rendering boundaries (%s)',
  locale => {
    beforeEach(() => {
      config.global.plugins = [
        createI18n({
          legacy: false,
          locale,
          messages: { en, es },
          missingWarn: false,
        }),
      ];
    });

    it('renders rich shared header, description and radio label props without leaking markers', () => {
      const wrapper = mount(
        defineComponent({
          setup() {
            const { nameRich, nameRichFrom } = useAssistantName({
              name: 'Aurora',
            });
            const text = nameRich('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.TOGGLE');
            return () =>
              h('div', [
                h(SettingsToggleSection, { header: text, description: text }),
                h(RadioCard, {
                  id: 'everyone',
                  label: text,
                  description: nameRichFrom('Captain'),
                }),
                h(SettingsHeader, { heading: 'Settings', description: text }),
              ]);
          },
        })
      );
      expect(wrapper.findAll('.assistant-name')).toHaveLength(5);
      expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
      expect(wrapper.text()).not.toContain('{assistantName}');
      wrapper.unmount();
    });

    it.each([{}, { name: 'Aurora' }, { name: 'Aurora'.repeat(6) }])(
      'keeps CSAT visible labels rich and accessible labels plain: %s',
      assistant => {
        const wrapper = mount(CsatCard, {
          props: { assistant },
          global: {
            stubs: {
              Popover: {
                template:
                  '<div><slot :is-open="false" /><slot name="content" /></div>',
              },
            },
          },
        });
        expect(wrapper.findAll('.assistant-name')).toHaveLength(3);
        expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
        expect(wrapper.text()).not.toContain('{assistantName}');
        wrapper.findAll('[aria-label]').forEach(element => {
          expect(element.attributes('aria-label')).not.toContain(
            ASSISTANT_NAME_MARKER
          );
        });
        if (assistant.name) {
          expect(wrapper.get('.assistant-name').attributes('title')).toBe(
            assistant.name
          );
        }
        wrapper.unmount();
      }
    );
  }
);
