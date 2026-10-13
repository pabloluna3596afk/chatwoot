import { createI18n } from 'vue-i18n';

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
