import { createI18n } from 'vue-i18n';
import { config, mount } from '@vue/test-utils';
import en from './locale/en';
import es from './locale/es';
import ContentTemplateParser from '../components-next/content-templates/ContentTemplateParser.vue';
import { generateSnoozeSuggestions } from '../helper/snoozeHelpers';

// vue-i18n compiles a message the first time it is shown. A message it cannot compile breaks the whole component that
// renders it. Typical causes: a bare "@" (read as a linked message "@:other.key": "Invalid linked format"; write a
// literal "@" as {'@'}) and literal double braces ("Not allowed nest placeholder"; write {'{'}{'{'} x {'}'}{'}'}).
// This guard compiles every message of every Spanish and English locale file.
const modules = import.meta.glob('./locale/{es,en}/*.json', { eager: true });

const leaves = (value, path = []) => {
  if (typeof value === 'string') return [[path.join('.'), value]];
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value).flatMap(([key, child]) =>
    leaves(child, [...path, key])
  );
};

describe('locale messages compile without errors', () => {
  it.each(Object.keys(modules))('%s', file => {
    const locale = file.includes('/es/') ? 'es' : 'en';
    const data = modules[file].default;
    const i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: false,
      missingWarn: false,
      messages: { [locale]: data },
    });
    // vue-i18n reports a message it cannot compile on the console and shows the raw key; some builds throw.
    const logged = [];
    const spies = ['error', 'warn'].map(level =>
      vi.spyOn(console, level).mockImplementation((...args) => {
        logged.push(args.map(String).join(' '));
      })
    );
    const failures = leaves(data).flatMap(([key]) => {
      try {
        i18n.global.t(key);
        return [];
      } catch (error) {
        return [`${key}: ${error.message}`];
      }
    });
    spies.forEach(spy => spy.mockRestore());
    // HTML in a message is intentional in a few places; only compilation errors matter here.
    const compileErrors = logged.filter(
      line => !line.includes('Detected HTML')
    );
    expect([...failures, ...compileErrors].slice(0, 5)).toEqual([]);
  });
});

describe.each(['en', 'es'])('effective %s locale messages', locale => {
  const messages = { en, es };
  const defaultPlugins = config.global.plugins;

  afterEach(() => {
    config.global.plugins = defaultPlugins;
  });

  it.each(['contentTemplates', 'snooze', 'yearInReview', 'calls'])(
    'exports every leaf of %s without fallback',
    catalog => {
      const data = modules[`./locale/${locale}/${catalog}.json`].default;
      const i18n = createI18n({
        legacy: false,
        locale,
        fallbackLocale: false,
        messages,
      });

      leaves(data).forEach(([key, value]) => {
        expect(i18n.global.te(key), key).toBe(true);
        expect(i18n.global.tm(key), key).toEqual(value);
        expect(i18n.global.t(key), key).not.toBe(key);
      });
    }
  );

  it('renders template labels, interpolations and validation from the effective locale', async () => {
    const i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: false,
      messages,
    });
    config.global.plugins = [i18n];
    const wrapper = mount(ContentTemplateParser, {
      props: {
        template: {
          friendly_name: 'appointment_reminder',
          language: 'es',
          body: 'Hola {{1}}',
        },
      },
    });

    try {
      expect(wrapper.text()).toContain(
        `${messages[locale].CONTENT_TEMPLATES.PARSER.LANGUAGE}: es`
      );
      expect(wrapper.find('input').attributes('placeholder')).toBe(
        i18n.global.t('CONTENT_TEMPLATES.PARSER.VARIABLE_PLACEHOLDER', {
          variable: '1',
        })
      );
      wrapper.vm.sendMessage();
      await wrapper.vm.$nextTick();
      expect(wrapper.text()).toContain(
        messages[locale].CONTENT_TEMPLATES.PARSER.FORM_ERROR_MESSAGE
      );
      expect(wrapper.emitted('sendMessage')).toBeUndefined();
      expect(wrapper.text()).not.toContain('CONTENT_TEMPLATES.');
    } finally {
      wrapper.unmount();
    }
  });

  it.each([
    ['tomorrow', 17, 9],
    ['2 hours', 16, 12],
  ])(
    'parses localized %s using the dictionary read by commandbar',
    (query, day, hour) => {
      const i18n = createI18n({
        legacy: false,
        locale,
        fallbackLocale: false,
        messages,
      });
      const translations = i18n.global.tm('SNOOZE_PARSER');
      const search =
        query === 'tomorrow'
          ? translations.RELATIVE.TOMORROW
          : `2 ${translations.UNITS.HOURS}`;
      const suggestions = generateSnoozeSuggestions(
        search,
        new Date(2026, 5, 16, 10),
        { translations, locale }
      );

      expect(suggestions.length).toBeGreaterThan(0);
      expect(suggestions[0].date).toEqual(new Date(2026, 5, day, hour));
      expect(suggestions[0].label.toLowerCase()).toContain(
        search.toLowerCase()
      );
      expect(suggestions[0].unixTime).toBe(
        suggestions[0].date.getTime() / 1000
      );
    }
  );
});
