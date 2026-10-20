import { catalogBindings, defaultValuesFor } from '../templateVariableBindings';
import catalog from 'dashboard/components-next/variable-picker/specs/catalog.json';

describe('Meta alias facade over server descriptors', () => {
  it('preserves server aliases when a literal key needs a generated Meta name', () => {
    const literal = catalog.variables.find(
      variable => variable.reference.definitionId === 14
    );
    const existing = {
      ...literal,
      id: 'contact.custom_attribute:20',
      aliases: ['atributo_14'],
    };
    const bindings = catalogBindings([literal, existing]);
    expect(bindings.map(binding => binding.name)).toEqual([
      'atributo_14_',
      'atributo_14',
    ]);
    expect(defaultValuesFor(bindings)[bindings[0].name]).toBe(
      literal.expression
    );
  });
  it('preserves aliases and uses the exact literal server expression for defaults', () => {
    const bindings = catalogBindings(catalog.variables);
    const defaults = defaultValuesFor(bindings);
    expect(defaults.nombre).toBe('{{ contact.name }}');
    expect(defaults.atributo_14).toBe(
      "{{ contact.custom_attribute['nivel-vip'] }}"
    );
    expect(defaults.atributo_15).toBe(
      "{{ contact.custom_attribute['nivel.vip'] }}"
    );
    expect(defaults.atributo_16).toBe(
      "{{ contact.custom_attribute['categoría'] }}"
    );
    expect(defaults.fecha).toBeUndefined();
    expect(defaults.atributo_17).toBeUndefined();
  });
  it('keeps company and Flow groups and definition identities when available', () => {
    const company = { ...catalog.variables.at(-1), available: true };
    const bindings = catalogBindings([company]);
    expect(bindings[0].scope).toBe('company');
    expect(bindings[0].reference.definitionId).toBe(17);
    expect(bindings[0].key).toBe("company.custom_attribute['company_context']");
  });
});
