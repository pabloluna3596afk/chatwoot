import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en';
import es from 'dashboard/i18n/locale/es';
import { getSuggestedRules } from './suggestedRules';

const examples = {
  en: [
    'Block queries that share or request sensitive personal information (e.g. phone numbers, passwords).',
    'Reject queries that include offensive, discriminatory, or threatening language.',
    'Deflect when the assistant is asked for legal or medical diagnosis or treatment.',
  ],
  es: [
    'Bloquea las consultas que compartan o soliciten datos personales sensibles, como teléfonos o contraseñas.',
    'Rechaza las consultas con lenguaje ofensivo, discriminatorio o amenazante.',
    'Deriva las consultas que soliciten un diagnóstico o tratamiento médico o legal.',
  ],
};

describe('Captain suggested rules', () => {
  it.each(['en', 'es'])(
    'returns the %s examples from the active locale',
    locale => {
      const messages = { en, es };
      const i18n = createI18n({
        legacy: false,
        locale,
        fallbackLocale: false,
        messages: { [locale]: messages[locale] },
      });

      expect(
        getSuggestedRules(i18n.global.t).map(({ content }) => content)
      ).toEqual(examples[locale]);
    }
  );
});
