import { mount } from '@vue/test-utils';
import Button from '../Button.vue';

const intentStyles = {
  primary: { color: 'blue', variant: 'solid' },
  secondary: { color: 'slate', variant: 'faded' },
  tertiary: { color: 'slate', variant: 'ghost' },
  link: { color: 'blue', variant: 'link' },
  destructive: { color: 'ruby', variant: 'solid' },
};

describe('Button intent', () => {
  it.each(Object.entries(intentStyles))(
    'maps %s to its color and variant defaults',
    (intent, style) => {
      const withIntent = mount(Button, {
        props: { label: 'Action', intent },
      });
      const explicitStyle = mount(Button, {
        props: { label: 'Action', ...style },
      });

      expect(withIntent.classes()).toEqual(explicitStyle.classes());
    }
  );

  it.each([
    ['primary', { color: 'ruby' }, {}],
    ['secondary', { variant: 'outline' }, {}],
    ['tertiary', {}, { ghost: '' }],
    ['destructive', {}, { blue: '', outline: '' }],
    ['link', { color: 'teal', variant: 'faded' }, {}],
  ])('preserves existing overrides for %s', (intent, overrides, attrs) => {
    const withIntent = mount(Button, {
      props: { label: 'Action', intent, ...overrides },
      attrs,
    });
    const withoutIntent = mount(Button, {
      props: { label: 'Action', ...overrides },
      attrs,
    });

    expect(withIntent.classes()).toEqual(withoutIntent.classes());
  });

  it('ignores an invalid intent', () => {
    const invalid = mount(Button, {
      props: { label: 'Action', intent: 'danger' },
    });
    const defaultButton = mount(Button, { props: { label: 'Action' } });

    expect(invalid.classes()).toEqual(defaultButton.classes());
  });
});

describe('Button alignment', () => {
  it('supports spreading selector labels and keeps action buttons centered by default', () => {
    const selector = mount(Button, {
      props: { label: 'All states', justify: 'between' },
    });
    const action = mount(Button, { props: { label: 'Update contact' } });

    expect(selector.classes()).toContain('justify-between');
    expect(action.classes()).toContain('justify-center');
  });
});
