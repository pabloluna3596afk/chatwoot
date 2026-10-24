import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import Button from '../Button.vue';
import CalendarWeek from '../../../components/ui/DatePicker/components/CalendarWeek.vue';

const source = readFileSync(
  'app/javascript/dashboard/assets/scss/_next-colors.scss',
  'utf8'
);
const palettes = source
  .split('  .dark {')
  .map(section =>
    Object.fromEntries(
      [...section.matchAll(/--([\w-]+):\s*([\d., ]+);/g)].map(
        ([, name, value]) => [name, value.trim().split(/[ ,]+/).map(Number)]
      )
    )
  );

const composite = (color, background) =>
  color
    .slice(0, 3)
    .map(
      (value, index) =>
        value * (color[3] ?? 1) + background[index] * (1 - (color[3] ?? 1))
    );
const luminance = color =>
  color.reduce((sum, value, index) => {
    const channel = value / 255;
    return (
      sum +
      (channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4) *
        [0.2126, 0.7152, 0.0722][index]
    );
  }, 0);

// Resolve the rendered utility classes in each state, including alpha over the real surface.
const pairFor = (classes, theme, state, surface) => {
  const palette = palettes[theme];
  const resolved = { bg: palette[surface] };
  const priorities = {};
  classes.forEach(className => {
    const parts = className.split(':');
    const rawUtility = parts.pop();
    const utility = rawUtility.replace(/^!/, '');
    if (parts.includes('dark') && !theme) return;
    if (parts.includes('hover') && state !== 'hover') return;
    if (parts.includes('focus-visible') && state !== 'focus-visible') return;
    const match = utility.match(/^(bg|text)-(white|n-[\w-]+)(?:\/(\d+))?$/);
    if (!match) return;
    const [, role, token, opacity] = match;
    const color =
      { white: [255, 255, 255], 'n-brand': [39, 129, 246] }[token] ??
      palette[token.slice(2)];
    if (!color) return;
    const priority = parts.length + (rawUtility.startsWith('!') ? 10 : 0);
    if (priority < (priorities[role] ?? -1)) return;
    priorities[role] = priority;
    resolved[role] = opacity
      ? [...color.slice(0, 3), Number(opacity) / 100]
      : color;
  });
  const background = composite(resolved.bg, palette[surface]);
  const foreground = composite(resolved.text, background);
  const values = [luminance(background), luminance(foreground)];
  return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
};

describe('button text contrast', () => {
  ['blue', 'ruby', 'teal', 'amber', 'slate'].forEach(color => {
    ['solid', 'faded', 'outline', 'ghost', 'link'].forEach(variant => {
      it(`${color} ${variant} reaches 4.5:1 on light and dark surfaces in all enabled states`, () => {
        const wrapper = mount(Button, {
          props: { color, variant, label: 'Action' },
        });
        [0, 1].forEach(theme => {
          ['default', 'hover', 'focus-visible'].forEach(state => {
            ['surface-1', 'solid-2'].forEach(surface => {
              expect(
                pairFor(wrapper.classes(), theme, state, surface),
                `${theme}/${state}/${surface}`
              ).toBeGreaterThanOrEqual(4.5);
            });
          });
        });
      });
    });
  });
});

describe('selected calendar date contrast', () => {
  it('keeps selected dates legible on hover in both themes', () => {
    const date = new Date(2026, 9, 15);
    const wrapper = mount(CalendarWeek, {
      props: {
        currentDate: date,
        startCurrentDate: date,
        endCurrentDate: date,
        selectedStartDate: date,
        selectedEndDate: date,
      },
    });
    const selectedDay = wrapper
      .findAll('.cursor-pointer')
      .find(day => day.text() === '15');
    [0, 1].forEach(theme => {
      ['default', 'hover'].forEach(state => {
        expect(
          pairFor(selectedDay.classes(), theme, state, 'surface-1')
        ).toBeGreaterThanOrEqual(4.5);
      });
    });
  });
});
