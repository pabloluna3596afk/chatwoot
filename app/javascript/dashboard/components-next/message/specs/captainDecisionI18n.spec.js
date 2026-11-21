import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';

const flatten = (value, prefix = '') =>
  Object.entries(value).flatMap(([key, item]) =>
    typeof item === 'object'
      ? flatten(item, `${prefix}${key}.`)
      : [[`${prefix}${key}`, item]]
  );

describe('Captain decision translations', () => {
  it('maintains en/es key and placeholder parity', () => {
    const english = flatten(en.CONVERSATION.CAPTAIN_DECISION);
    const spanish = new Map(flatten(es.CONVERSATION.CAPTAIN_DECISION));
    expect(english.map(([key]) => key).sort()).toEqual(
      [...spanish.keys()].sort()
    );
    english.forEach(([key, text]) => {
      expect(text.match(/\{\w+\}/g) || []).toEqual(
        spanish.get(key).match(/\{\w+\}/g) || []
      );
      expect(text).not.toMatch(
        /[\u3400-\u9fff]|\b(?:detalles|créditos|después|decisión)\b/i
      );
      expect(spanish.get(key)).not.toMatch(
        /[\u3400-\u9fff]|\b(?:tenés|podés|hacé|reintentá|cambiá)\b/i
      );
      expect(spanish.get(key)).not.toContain('?');
    });
    expect(Object.keys(en.MESSAGE_META)).toEqual(Object.keys(es.MESSAGE_META));
    expect(es.CONVERSATION.CAPTAIN_DECISION.OPEN).toBe(
      'Ver detalles de la decisión de Captain'
    );
  });

  it('localizes the recorded follow-up settings and exact control facts', () => {
    [en, es].forEach(locale => {
      const copy = locale.CONVERSATION.CAPTAIN_DECISION;
      [
        'inactivityAfterMinutes',
        'maxNudges',
        'maxRepliesPerConversation',
      ].forEach(setting =>
        expect(copy.SETTINGS[setting]).toContain('{minutes}')
      );
      ['human_control', 'disengage'].forEach(fact => {
        expect(copy.LATER[fact]).toBeTruthy();
      });
    });
  });
});
