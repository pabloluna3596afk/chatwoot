import routes from './helpcenter.routes';

describe('Help Center management navigation', () => {
  it('requires administrator or knowledge base management permission on every management route', () => {
    const root = routes.routes;
    const managementRoutes = root.flatMap(route => route.children || [route]);
    expect(managementRoutes.length).toBeGreaterThan(0);
    managementRoutes.forEach(route => {
      expect(route.meta.permissions).toEqual([
        'administrator',
        'knowledge_base_manage',
      ]);
    });
  });
});
