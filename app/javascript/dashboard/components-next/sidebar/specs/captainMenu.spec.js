import { buildCaptainMenu } from '../captainMenu';

const build = isAdmin =>
  buildCaptainMenu({
    isAdmin,
    t: key => key,
    accountScopedRoute: (name, params) => ({ name, params }),
  });

describe('Captain sidebar menu', () => {
  it('hides Settings and Scenarios for agents while keeping Inboxes and Tools', () => {
    const names = build(false).map(({ name }) => name);

    expect(names).not.toContain('Settings');
    expect(names).not.toContain('Scenarios');
    expect(names).toContain('Inboxes');
    expect(names).toContain('Tools');
  });

  it('shows Settings and Scenarios for administrators', () => {
    const names = build(true).map(({ name }) => name);

    expect(names).toContain('Settings');
    expect(names).toContain('Scenarios');
  });
});
