import { required, minLength, helpers } from '@vuelidate/validators';

export default t => ({
  title: {
    required: helpers.withMessage(
      () => t('GENERAL.VALIDATION.REQUIRED'),
      required
    ),
    minLength: helpers.withMessage(
      ({ $params }) => t('GENERAL.VALIDATION.MIN_LENGTH', { min: $params.min }),
      minLength(2)
    ),
  },
  description: {},
  showOnSidebar: {},
});
