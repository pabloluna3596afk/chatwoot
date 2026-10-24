import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import Button from '../Button.vue';
import CalendarWeek from '../../../components/ui/DatePicker/components/CalendarWeek.vue';

const source = readFileSync(
  'app/javascript/dashboard/assets/scss/_next-colors.scss',
  'utf8'
);
const brand = readFileSync('theme/colors.js', 'utf8')
  .match(/brand: '#([a-f\d]{6})'/i)[1]
  .match(/.{2}/g)
  .map(channel => parseInt(channel, 16));
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

// Frozen develop color contract: dark colors and the approved unchanged variants.
const baseline = {
  colors: {
    blue: {
      solid:
        'bg-n-brand text-white hover:enabled:brightness-110 focus-visible:brightness-110 outline-transparent',
      faded:
        'bg-n-brand/10 text-n-blue-11 hover:enabled:bg-n-brand/20 focus-visible:bg-n-brand/20 outline-transparent',
      outline: 'text-n-blue-11 outline-n-brand',
      ghost:
        'text-n-blue-11 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent',
      link: 'text-n-blue-11 hover:enabled:underline focus-visible:underline outline-transparent',
    },
    ruby: {
      solid:
        'bg-n-ruby-9 text-white hover:enabled:bg-n-ruby-10 focus-visible:bg-n-ruby-10 outline-transparent',
      faded:
        'bg-n-ruby-9/10 text-n-ruby-11 hover:enabled:bg-n-ruby-9/20 focus-visible:bg-n-ruby-9/20 outline-transparent',
      outline:
        'text-n-ruby-11 hover:enabled:bg-n-ruby-9/10 focus-visible:bg-n-ruby-9/10 outline-n-ruby-8',
      ghost:
        'text-n-ruby-11 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent',
      link: 'text-n-ruby-9 dark:text-n-ruby-11 hover:enabled:underline focus-visible:underline outline-transparent',
    },
    amber: {
      solid:
        'bg-n-amber-9 text-n-amber-12 dark:text-n-amber-3 hover:enabled:bg-n-amber-10 focus-visible:bg-n-amber-10 outline-transparent',
      faded:
        'bg-n-amber-9/10 text-n-slate-12 hover:enabled:bg-n-amber-9/20 focus-visible:bg-n-amber-9/20 outline-transparent',
      outline:
        'text-n-amber-11 hover:enabled:bg-n-amber-9/10 focus-visible:bg-n-amber-9/10 outline-n-amber-9',
      link: 'text-n-amber-9 hover:enabled:underline focus-visible:underline outline-transparent',
      ghost:
        'text-n-amber-9 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent',
    },
    slate: {
      solid:
        'bg-n-button-color dark:hover:enabled:bg-n-solid-2 dark:focus-visible:bg-n-solid-2 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 text-n-slate-12 outline-n-container',
      faded:
        'bg-n-slate-9/10 text-n-slate-12 hover:enabled:bg-n-slate-9/20 focus-visible:bg-n-slate-9/20 outline-transparent',
      outline:
        'text-n-slate-11 outline-n-strong hover:enabled:bg-n-slate-9/10 focus-visible:bg-n-slate-9/10',
      link: 'text-n-slate-11 hover:enabled:text-n-slate-12 focus-visible:text-n-slate-12 hover:enabled:underline focus-visible:underline outline-transparent',
      ghost:
        'text-n-slate-12 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent',
    },
    teal: {
      solid:
        'bg-n-teal-9 text-white hover:enabled:bg-n-teal-10 focus-visible:bg-n-teal-10 outline-transparent',
      faded:
        'bg-n-teal-9/10 text-n-teal-11 hover:enabled:bg-n-teal-9/20 focus-visible:bg-n-teal-9/20 outline-transparent',
      outline:
        'text-n-teal-11 hover:enabled:bg-n-teal-9/10 focus-visible:bg-n-teal-9/10 outline-n-teal-9',
      link: 'text-n-teal-9 hover:enabled:underline focus-visible:underline outline-transparent',
      ghost:
        'text-n-teal-9 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent',
    },
  },
};

// Resolve the rendered utility classes in each state, including alpha over the real surface.
const colorsFor = (classes, theme, state, surface) => {
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
      { white: [255, 255, 255], 'n-brand': brand }[token] ??
      palette[token.slice(2)];
    expect(color, `Missing token: ${token}`).toBeDefined();
    const priority = parts.length + (rawUtility.startsWith('!') ? 10 : 0);
    if (priority < (priorities[role] ?? -1)) return;
    priorities[role] = priority;
    resolved[role] = opacity
      ? [...color.slice(0, 3), Number(opacity) / 100]
      : color;
  });
  const background = composite(resolved.bg, palette[surface]);
  let foreground = composite(resolved.text, background);
  const brightens = classes.some(
    className =>
      className === `${state}:brightness-110` ||
      className === `${state}:enabled:brightness-110`
  );
  if (brightens) {
    foreground = foreground.map(value => Math.min(255, value * 1.1));
    return {
      foreground,
      background: background.map(value => Math.min(255, value * 1.1)),
    };
  }
  return { foreground, background };
};

const pairFor = (classes, theme, state, surface) => {
  const { foreground, background } = colorsFor(classes, theme, state, surface);
  const values = [luminance(background), luminance(foreground)];
  return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
};

describe('button color contract', () => {
  const corrected = [
    'teal/solid',
    'teal/faded',
    'teal/outline',
    'teal/ghost',
    'teal/link',
    'amber/ghost',
    'amber/link',
    'ruby/link',
  ];
  Object.entries(baseline.colors).forEach(([color, variants]) => {
    Object.entries(variants).forEach(([variant, originalClasses]) => {
      describe(`${color} ${variant}`, () => {
        const classes = () =>
          mount(Button, {
            props: { color, variant, label: 'Action' },
          }).classes();
        const original = originalClasses.split(' ');
        ['default', 'hover', 'focus-visible'].forEach(state => {
          ['surface-1', 'solid-2'].forEach(surface => {
            it(`preserves develop dark colors: ${state}/${surface}`, () => {
              expect(colorsFor(classes(), 1, state, surface)).toEqual(
                colorsFor(original, 1, state, surface)
              );
            });
            it(`measures the light pair: ${state}/${surface}`, () => {
              if (corrected.includes(`${color}/${variant}`)) {
                expect(
                  pairFor(classes(), 0, state, surface)
                ).toBeGreaterThanOrEqual(4.5);
              } else {
                // Owner explicitly preserves blue/ruby solids and all other variants.
                expect(colorsFor(classes(), 0, state, surface)).toEqual(
                  colorsFor(original, 0, state, surface)
                );
              }
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
