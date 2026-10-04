import { PRESETS, PRESET_GROUPS, presetToForm } from '../presets';
import {
  buildPayload,
  hasNamedVariables,
  validateForm,
  variableTokens,
} from '../templateForm';

describe('presets', () => {
  it('has the eight presets in the three groups', () => {
    expect(PRESETS).toHaveLength(8);
    expect(new Set(PRESETS.map(preset => preset.group))).toEqual(
      new Set(PRESET_GROUPS)
    );
  });

  it.each(PRESETS.map(preset => [preset.id, preset]))(
    '%s is a valid template with named variables',
    (_id, preset) => {
      const form = presetToForm(preset, 1);

      expect(validateForm(form)).toEqual({});
      expect(hasNamedVariables(form.body.text)).toBe(true);
      expect(buildPayload(form).body.examples).toHaveLength(
        variableTokens(form.body.text).length
      );
    }
  );

  it('uses only the variables Captain fills in (or the topic) and neutral Spanish', () => {
    const allowed = ['nombre', 'cita', 'fecha', 'hora', 'tema'];

    PRESETS.forEach(preset => {
      variableTokens(preset.body).forEach(token => {
        expect(allowed).toContain(token);
      });
      expect(preset.body).not.toMatch(/\b(vos|tenés|querés|podés|respondé)\b/i);
    });
  });

  it('labels every preset UTILITY or MARKETING and gives marketing an opt-out line', () => {
    PRESETS.forEach(preset => {
      expect(['UTILITY', 'MARKETING']).toContain(preset.category);
      if (preset.category === 'MARKETING') {
        expect(preset.footer).toBe(
          'Responde BAJA si no quieres recibir más mensajes'
        );
      }
    });
  });

  it('keeps the customer data preset for when forms exist', () => {
    expect(PRESETS.find(preset => preset.id === 'datos_cliente').disabled).toBe(
      true
    );
    expect(PRESETS.filter(preset => preset.disabled)).toHaveLength(1);
  });

  it('opens the form with the preset name, category, body, footer and buttons', () => {
    const form = presetToForm(
      PRESETS.find(preset => preset.id === 'recordatorio_cita'),
      4
    );

    expect(form).toMatchObject({
      inboxId: 4,
      name: 'recordatorio_cita',
      language: 'es',
      category: 'UTILITY',
    });
    expect(form.buttons.map(button => button.text)).toEqual([
      'Confirmo',
      'Cambiar hora',
      'Cancelar cita',
    ]);
  });
});
