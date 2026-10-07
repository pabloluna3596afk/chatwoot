import conditions from '../../../../config/whatsapp_flow_conditions.json';

export const CONDITION_TYPES = conditions.types;

// The same operators/types drive the Ruby validator and Meta expression exporter.
export const evaluateVisibility = (block, answers) => {
  const condition = block.visible_when;
  if (!condition?.key) return true;
  const matches =
    String(answers[condition.key] ?? '') === String(condition.value);
  return conditions.operators[condition.op] === '!=' ? !matches : matches;
};

export const answerBlocks = definition =>
  definition.screens.flatMap(screen =>
    screen.blocks.filter(block => block.key)
  );

const isEmpty = value =>
  value === undefined ||
  value === null ||
  (typeof value === 'string' && !value.trim()) ||
  (Array.isArray(value) && !value.length);

// Earlier fields are evaluated first; hidden answers never feed later conditions.
export const collectAnswers = (definition, answers) => {
  const collected = {};
  answerBlocks(definition).forEach(block => {
    if (!evaluateVisibility(block, collected) || isEmpty(answers[block.key]))
      return;
    const value = answers[block.key];
    collected[block.key] = block.type === 'short_text' ? String(value) : value;
  });
  return collected;
};

export const validateAnswers = (screen, answers) =>
  Object.fromEntries(
    screen.blocks.flatMap(block => {
      if (!block.key || !evaluateVisibility(block, answers)) return [];
      const value = answers[block.key];
      if (block.required && (isEmpty(value) || value === false))
        return [[block.key, 'REQUIRED']];
      if (isEmpty(value)) return [];
      if (block.type === 'short_text') {
        if (
          block.input === 'email' &&
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
        )
          return [[block.key, 'EMAIL']];
        if (block.input === 'number' && !Number.isFinite(Number(value)))
          return [[block.key, 'NUMBER']];
      }
      if (['checkbox', 'photo', 'document'].includes(block.type)) {
        const min = block.type === 'checkbox' ? block.min : block.min_files;
        const max = block.type === 'checkbox' ? block.max : block.max_files;
        if ((min > 0 && value.length < min) || (max > 0 && value.length > max))
          return [[block.key, 'SELECTION']];
      }
      return [];
    })
  );
