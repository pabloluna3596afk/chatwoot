// The attribute modals are used from the template editor and the Flow editor too: no browser <select> inside them,
// help texts live in tooltips, and the two pickers (Aplicar a, Tipo) are the shared ComboBox.
const sources = import.meta.glob(
  ['../AddAttribute.vue', '../EditAttribute.vue'],
  {
    query: '?raw',
    import: 'default',
    eager: true,
  }
);

describe.each(Object.entries(sources))('%s', (file, source) => {
  it('has no native select', () => {
    expect(source).not.toContain('<select');
  });

  it('uses the shared ComboBox for its pickers', () => {
    expect(source).toContain('<ComboBox');
  });
});
