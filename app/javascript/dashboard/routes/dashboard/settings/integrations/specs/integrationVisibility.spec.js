import { describe, expect, it } from 'vitest';
import { isIntegrationVisible } from '../integrationVisibility';

describe('isIntegrationVisible', () => {
  it('hides Dialogflow when it has no configured hooks', () => {
    expect(isIntegrationVisible({ id: 'dialogflow', hooks: [] })).toBe(false);
  });

  it('keeps configured Dialogflow available for editing', () => {
    expect(isIntegrationVisible({ id: 'dialogflow', hooks: [{ id: 1 }] })).toBe(
      true
    );
  });

  it('keeps other integrations visible', () => {
    expect(isIntegrationVisible({ id: 'slack', hooks: [] })).toBe(true);
  });
});
