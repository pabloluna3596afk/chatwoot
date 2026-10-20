/* Catalog field keys are defined by the API contract. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { useI18n } from 'vue-i18n';

export const planViewProps = {
  context: { type: String, default: 'billing' },
  requiredFeature: { type: String, default: '' },
  currentPlanId: { type: [Number, String], default: null },
  selectedPlanId: { type: [Number, String], default: null },
  canSelect: { type: Boolean, default: false },
};

export const matchesPlan = (plan, id) =>
  id !== null && (plan.id === id || plan.slug === id);

// Presentation metadata describes the API fields, never commercial plan values.
const LIMIT_ICONS = {
  inboxes: 'i-lucide-inbox',
  assistants: 'i-woot-captain',
  monthly_responses: 'i-lucide-sparkles',
  users: 'i-lucide-users',
  storage_bytes: 'i-lucide-hard-drive',
  emails_per_day: 'i-lucide-mail',
  tests_per_day: 'i-lucide-flask-conical',
  trial_days: 'i-lucide-calendar',
  trial_responses: 'i-lucide-sparkles',
};
export const SUMMARY_FIELDS = [
  'inboxes',
  'assistants',
  'monthly_responses',
  'users',
];
const MEBIBYTE = 1024 ** 2;
const GIBIBYTE = 1024 ** 3;

export function usePlanPresentation() {
  const { t, n, locale } = useI18n();
  const number = value =>
    n(
      value,
      { useGrouping: true, maximumFractionDigits: 2 },
      locale.value.startsWith('es') ? 'es-EC' : locale.value
    );
  const label = key => t(`PLAN_CATALOG.LIMITS.${key}`);
  const value = (key, amount) => {
    if (amount === null || amount === undefined)
      return t('PLAN_CATALOG.UNKNOWN');
    if (key === 'storage_bytes') {
      const unit = amount >= GIBIBYTE ? 'GB' : 'MB';
      return t(`PLAN_CATALOG.${unit}`, {
        count: number(amount / (unit === 'GB' ? GIBIBYTE : MEBIBYTE)),
      });
    }
    return number(amount);
  };
  const summary = plan =>
    SUMMARY_FIELDS.filter(
      key => plan.limits[key] !== null && plan.limits[key] !== undefined
    ).map(key => ({
      key,
      icon: LIMIT_ICONS[key],
      text: t(
        `PLAN_CATALOG.COUNTS.${key}`,
        { count: number(plan.limits[key]) },
        plan.limits[key]
      ),
    }));
  const rows = plans =>
    [...new Set(plans.flatMap(plan => Object.keys(plan.limits)))].map(key => ({
      key,
      label: label(key),
      icon: LIMIT_ICONS[key],
    }));
  const features = plans => [
    ...new Set(plans.flatMap(plan => plan.feature_keys)),
  ];
  return {
    label,
    value,
    summary,
    rows,
    features,
  };
}
