import ai from './ai.routes';

describe('AI settings route', () => {
  it('defines an administrator-only account settings page', () => {
    const [route] = ai.routes;
    const [index] = route.children;

    expect(route.path).toContain('accounts/:accountId/settings/ai');
    expect(route.meta.permissions).toEqual(['administrator']);
    expect(index.name).toBe('ai_settings_index');
    expect(index.meta.permissions).toEqual(['administrator']);
  });
});
