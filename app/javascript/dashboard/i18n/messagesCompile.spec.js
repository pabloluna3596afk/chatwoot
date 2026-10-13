import { createI18n } from 'vue-i18n';
import esIntegrations from './locale/es/integrations.json';
import enIntegrations from './locale/en/integrations.json';
import esTemplates from './locale/es/whatsappTemplateMgmt.json';
import enTemplates from './locale/en/whatsappTemplateMgmt.json';

// A message with a bare "@" is read by vue-i18n as a linked message ("@:other.key") and its compiler throws "Invalid
// linked format" the first time the message is shown, which breaks the whole component that renders it. Write a literal
// "@" as {'@'}.
const leaves = (value, path = []) => {
  if (typeof value === 'string') return [[path.join('.'), value]];
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value).flatMap(([key, child]) =>
    leaves(child, [...path, key])
  );
};

const files = {
  es: { ...esIntegrations, ...esTemplates },
  en: { ...enIntegrations, ...enTemplates },
};

describe.each(Object.keys(files))('messages of %s', locale => {
  const i18n = createI18n({
    legacy: false,
    locale,
    fallbackLocale: false,
    missingWarn: false,
    messages: { [locale]: files[locale] },
  });

  it('compile without errors', () => {
    // vue-i18n reports a message it cannot compile on the console and shows the raw key; some builds throw.
    const logged = [];
    const spies = ['error', 'warn'].map(level =>
      vi.spyOn(console, level).mockImplementation((...args) => {
        logged.push(args.map(String).join(' '));
      })
    );
    const failures = leaves(files[locale]).flatMap(([key, text]) => {
      logged.length = 0;
      try {
        i18n.global.t(key, { n: 1, count: 1, title: 'x' });
      } catch (error) {
        logged.push(error.message);
      }
      // Upstream messages that carry HTML only warn: they render fine.
      const problems = logged.filter(line => !line.includes('Detected HTML'));
      return problems.length
        ? [`${key}: ${problems.join(' / ')} (${text.slice(0, 60)})`]
        : [];
    });
    spies.forEach(spy => spy.mockRestore());

    expect(failures).toEqual([]);
  });
});
