/* Catalog field keys are defined by the API contract. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { useI18n } from 'vue-i18n';

export const planViewProps = {
  context: { type: String, default: 'billing' },
  requiredFeature: { type: String, default: '' },
  currentPlanId: { type: [Number, String], default: null },
  selectedPlanId: { type: [Number, String], default: null },
  canSelect: { type: Boolean, default: false },
  canPurchase: { type: Boolean, default: false },
};

export const matchesPlan = (plan, id) =>
  id !== null && (plan.id === id || plan.slug === id);

const MEBIBYTE = 1024 ** 2;
const GIBIBYTE = 1024 ** 3;
const SUMMARY_FIELDS = [
  'inboxes',
  'users',
  'assistants',
  'monthly_responses',
  'trial_responses',
  'storage_bytes',
];

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
  const limitValue = (plan, key) =>
    key === 'monthly_responses' && Number(plan.limits.trial_responses) > 0
      ? null
      : plan.limits[key];
  const summary = plan =>
    SUMMARY_FIELDS.filter(key => Number(limitValue(plan, key)) > 0).map(
      key => ({
        key,
        text:
          key === 'storage_bytes'
            ? `${label(key)}: ${value(key, plan.limits[key])}`
            : t(
                `PLAN_CATALOG.COUNTS.${key}`,
                { count: number(plan.limits[key]) },
                plan.limits[key]
              ),
      })
    );
  const rows = plans =>
    [...new Set(plans.flatMap(plan => Object.keys(plan.limits)))]
      .filter(key => plans.some(plan => Number(limitValue(plan, key)) > 0))
      .map(key => ({
        key,
        label: label(key),
      }));
  const features = plans => [
    ...new Set(plans.flatMap(plan => plan.feature_keys)),
  ];
  const baseFeatures = plans => {
    const [firstPlan, ...otherPlans] = plans;
    return (firstPlan?.base_feature_keys || []).filter(key =>
      otherPlans.every(plan => plan.base_feature_keys?.includes(key))
    );
  };
  const featureChanges = (plans, plan) => {
    const ordered = [...plans].sort(
      (left, right) =>
        (left.display_order ?? 0) - (right.display_order ?? 0) ||
        Number(left.id) - Number(right.id)
    );
    const index = ordered.findIndex(item => item.id === plan.id);
    const previousPlan = index > 0 ? ordered[index - 1] : null;
    const before = previousPlan?.feature_keys || [];
    return {
      previousPlan,
      added: plan.feature_keys.filter(key => !before.includes(key)),
      removed: before.filter(key => !plan.feature_keys.includes(key)),
    };
  };
  const money = amount =>
    new Intl.NumberFormat(
      locale.value.startsWith('es') ? 'es-EC' : locale.value,
      {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 2,
      }
    ).format(amount);
  const pricing = plan => ({
    monthly: Number(plan.price_monthly) || 0,
    annual: Number(plan.price_yearly) || 0,
  });
  return {
    label,
    value,
    limitValue,
    summary,
    rows,
    features,
    baseFeatures,
    featureChanges,
    money,
    pricing,
    isIncluded: amount => Number(amount) > 0,
  };
}
