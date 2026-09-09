import { filterUnactivatedPresets } from '../unactivatedPresets';

const presets = [
  { id: 'post_compra_n_dias' },
  { id: 'followup_sin_respuesta' },
  { id: 'seguimiento_30d' },
];

describe('filterUnactivatedPresets', () => {
  it('returns all presets when no automation rule has a matching preset_id', () => {
    const rules = [{ id: 1, preset_id: null }, { id: 2 }];
    expect(filterUnactivatedPresets(presets, rules)).toEqual(presets);
  });

  it('drops a preset once a rule created from it exists — the CRM should not offer to duplicate it', () => {
    const rules = [{ id: 1, preset_id: 'post_compra_n_dias' }];
    const result = filterUnactivatedPresets(presets, rules);
    expect(result.map(p => p.id)).toEqual([
      'followup_sin_respuesta',
      'seguimiento_30d',
    ]);
  });

  it('drops a preset even if the rule created from it was later disabled', () => {
    const rules = [{ id: 1, preset_id: 'post_compra_n_dias', active: false }];
    const result = filterUnactivatedPresets(presets, rules);
    expect(result.map(p => p.id)).not.toContain('post_compra_n_dias');
  });

  it('offers the preset again once the rule that used it is gone', () => {
    const rules = [{ id: 1, preset_id: 'seguimiento_30d' }];
    const afterDeletion = filterUnactivatedPresets(presets, []);
    expect(afterDeletion).toEqual(presets);
    // sanity: confirms the fixture actually filtered something before deletion
    expect(filterUnactivatedPresets(presets, rules)).not.toEqual(presets);
  });

  it('handles missing/undefined rules without throwing', () => {
    expect(filterUnactivatedPresets(presets, undefined)).toEqual(presets);
    expect(filterUnactivatedPresets(presets, null)).toEqual(presets);
  });

  it('handles missing/undefined presets without throwing', () => {
    expect(filterUnactivatedPresets(undefined, [])).toEqual([]);
    expect(filterUnactivatedPresets(null, [])).toEqual([]);
  });
});
