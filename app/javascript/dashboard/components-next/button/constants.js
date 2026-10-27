export const VARIANT_OPTIONS = ['solid', 'outline', 'faded', 'link', 'ghost'];
export const COLOR_OPTIONS = ['blue', 'ruby', 'amber', 'slate', 'teal'];
export const INTENT_OPTIONS = [
  'primary',
  'secondary',
  'tertiary',
  'link',
  'destructive',
];
export const INTENT_STYLES = {
  primary: { color: 'blue', variant: 'solid' },
  secondary: { color: 'slate', variant: 'faded' },
  tertiary: { color: 'slate', variant: 'ghost' },
  link: { color: 'blue', variant: 'link' },
  destructive: { color: 'ruby', variant: 'solid' },
};
export const SIZE_OPTIONS = ['xs', 'sm', 'md', 'lg'];
export const JUSTIFY_OPTIONS = ['start', 'center', 'end', 'between'];

export const EXCLUDED_ATTRS = [
  'variant',
  'color',
  'size',
  'icon',
  'trailingIcon',
  'isLoading',
  ...VARIANT_OPTIONS,
  ...COLOR_OPTIONS,
  ...SIZE_OPTIONS,
  ...JUSTIFY_OPTIONS,
];
