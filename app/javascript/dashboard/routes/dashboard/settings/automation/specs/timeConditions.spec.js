import { AUTOMATIONS } from '../constants';
import { generateAutomationPayload } from 'dashboard/helper/automationHelper';
import { validateAutomation } from 'dashboard/helper/validations';

const CONVERSATION_EVENTS = [
  'message_created',
  'conversation_created',
  'conversation_updated',
  'conversation_opened',
  'conversation_resolved',
];

const condition = (event, key) =>
  AUTOMATIONS[event].conditions.find(item => item.key === key);

describe('time based automation conditions', () => {
  it.each(CONVERSATION_EVENTS)('are offered on %s', event => {
    expect(condition(event, 'within_business_hours')).toMatchObject({
      name: 'WITHIN_BUSINESS_HOURS',
      inputType: 'search_select',
      filterOperators: [{ value: 'equal_to' }],
    });
    expect(condition(event, 'message_time_window')).toMatchObject({
      name: 'MESSAGE_TIME_WINDOW',
      inputType: 'time_window',
      filterOperators: [
        { value: 'equal_to', label: 'AUTOMATION.TIME_WINDOW.OPERATOR_INSIDE' },
        {
          value: 'not_equal_to',
          label: 'AUTOMATION.TIME_WINDOW.OPERATOR_OUTSIDE',
        },
      ],
    });
  });

  it('are not offered on time triggered rules, which have no message', () => {
    expect(
      condition('time_triggered', 'within_business_hours')
    ).toBeUndefined();
    expect(condition('time_triggered', 'message_time_window')).toBeUndefined();
  });

  it('sends the window as the single string the server validates', () => {
    const payload = generateAutomationPayload({
      name: 'Night',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'message_time_window',
          filter_operator: 'equal_to',
          values: '18:00-08:00|mon,tue',
          query_operator: 'and',
        },
        {
          attribute_key: 'within_business_hours',
          filter_operator: 'equal_to',
          values: { id: false, name: 'False' },
          query_operator: 'and',
        },
      ],
      actions: [{ action_name: 'send_message', action_params: ['Hola'] }],
    });

    expect(payload.conditions.map(item => item.values)).toEqual([
      ['18:00-08:00|mon,tue'],
      [false],
    ]);
  });

  it('keeps the form from saving an incomplete or empty window', () => {
    const base = {
      name: 'Night',
      description: 'Night',
      event_name: 'message_created',
      actions: [{ action_name: 'add_label', action_params: ['night'] }],
    };
    const withWindow = values => ({
      ...base,
      conditions: [
        {
          attribute_key: 'message_time_window',
          filter_operator: 'equal_to',
          values,
        },
      ],
    });

    expect(validateAutomation(withWindow('18:00-08:00'))).toEqual({});
    expect(validateAutomation(withWindow(''))).toHaveProperty('condition_0');
    expect(validateAutomation(withWindow('08:00-08:00'))).toHaveProperty(
      'condition_0'
    );
  });
});
