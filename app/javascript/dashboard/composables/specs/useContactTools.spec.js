import { config, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { useContactTools } from '../useContactTools';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';

const typingRecords = ref([]);
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      'conversationTypingStatus/getUserList': () => typingRecords.value,
    },
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ calendar_timezone: 'America/Guayaquil' }),
  }),
}));

const chat = ref({});
const assistant = ref(null);
const connected = ref(false);
const nextEvent = ref(null);
const now = ref(new Date('2026-10-22T04:30:00Z'));
const openCalendar = vi.fn();
const originalPlugins = config.global.plugins;
afterAll(() => {
  config.global.plugins = originalPlugins;
});
let tools;
let wrapper;
const start = (locale = 'es') => {
  config.global.plugins = [
    createI18n({ legacy: false, locale, messages: { en, es } }),
  ];
  wrapper = mount({
    setup() {
      tools = useContactTools({
        chat,
        inboxAssistant: assistant,
        calendarConnected: connected,
        nextEvent,
        now,
        onOpenCalendar: openCalendar,
      });
      return () => null;
    },
  });
};

beforeEach(() => {
  chat.value = {};
  typingRecords.value = [];
  assistant.value = null;
  connected.value = false;
  nextEvent.value = null;
  now.value = new Date('2026-10-22T04:30:00Z');
});
afterEach(() => wrapper.unmount());

describe('useContactTools', () => {
  it('hides tools when unavailable and never registers payment or cart in the real panel', () => {
    start();
    expect(tools.value.map(tool => [tool.key, tool.state])).toEqual([
      ['captain', 'hidden'],
      ['calendar', 'hidden'],
    ]);
  });

  it.each([
    ['ai', 'active', 'Aurora está asignado'],
    ['escalated', 'warning', 'Aurora pasó la conversación al equipo'],
    ['human', 'idle', 'Captain no atiende esta conversación'],
  ])('maps Captain %s to %s with localized state', (state, expected, label) => {
    assistant.value = { name: 'Aurora' };
    chat.value = { captain_state: state };
    start();
    expect(tools.value[0].state).toBe(expected);
    expect(tools.value[0].label).toContain(label);
    chat.value = { captain_state: 'ai', captain_assistant: { name: 'Luna' } };
    expect(tools.value[0].legend).toBe('Luna está asignado');
    assistant.value = null;
    expect(tools.value[0].state).toBe('hidden');
  });

  it.each([
    ['es', 'ai', 0, 'Aurora está asignado'],
    ['es', 'ai', 1, 'Aurora está atento · esperando al cliente'],
    ['es', 'escalated', 1, 'Aurora pasó la conversación al equipo'],
    ['en', 'ai', 0, 'Aurora is assigned'],
    ['en', 'ai', 1, 'Aurora is attentive · waiting for the customer'],
    ['en', 'escalated', 1, 'Aurora handed the conversation to the team'],
  ])(
    'localizes %s Captain %s after message type %s',
    (locale, state, type, legend) => {
      assistant.value = { name: 'Aurora' };
      chat.value = { captain_state: state, messages: [{ message_type: type }] };
      start(locale);
      expect(tools.value[0].legend).toBe(legend);
      expect(tools.value[0].label).toBe(legend);
    }
  );

  it('uses Captain when the assistant has no name', () => {
    assistant.value = {};
    chat.value = { captain_state: 'ai' };
    start('en');
    expect(tools.value[0].legend).toBe('Captain is assigned');
  });

  it('shows a live typing state only for the assigned Captain assistant', () => {
    assistant.value = { id: 7, name: 'Aurora', avatar_url: '/aurora.png' };
    chat.value = {
      id: 1,
      captain_state: 'ai',
      captain_assistant: assistant.value,
      messages: [{ message_type: 0 }],
    };
    start('en');
    typingRecords.value = [{ id: 9, type: 'captain_assistant', name: 'Other' }];
    expect(tools.value[0].legend).toBe('Aurora is assigned');
    typingRecords.value = [
      { id: 7, type: 'captain_assistant', name: 'Aurora' },
    ];
    expect(tools.value[0].legend).toBe('Aurora is typing…');
    expect(tools.value[0].isTyping).toBe(true);
    expect(tools.value[0].assistantAvatar).toBe('/aurora.png');
  });

  it('opens creation for idle calendar and the accordion for an existing appointment', () => {
    connected.value = true;
    start();
    expect(tools.value[1].state).toBe('idle');
    expect(tools.value[1].label).toBe('Sin próximas citas · Agendar');
    tools.value[1].onClick();
    expect(openCalendar).toHaveBeenLastCalledWith(true);
    nextEvent.value = { start: '2026-10-22T15:00:00Z', summary: 'Consulta' };
    expect(tools.value[1].state).toBe('active');
    expect(tools.value[1].legend).toBe('Próxima cita: mañana 10:00');
    tools.value[1].onClick();
    expect(openCalendar).toHaveBeenLastCalledWith(false);
    now.value = new Date('2026-10-22T05:30:00Z');
    expect(tools.value[1].legend).toBe('Próxima cita: hoy 10:00');
    connected.value = false;
    expect(tools.value[1].state).toBe('hidden');
  });

  it('formats non-relative dates and English legends using the account timezone', () => {
    connected.value = true;
    nextEvent.value = {
      start: '2026-10-26T15:00:00Z',
      summary: 'Consultation',
    };
    start('en');
    expect(tools.value[1].legend).toContain('10:00');
    expect(tools.value[1].label).toBe('Consultation');
    expect(tools.value[1].legend).not.toContain('Consultation');
    nextEvent.value = {
      start: '2026-10-22T15:00:00Z',
      summary: 'Consultation',
    };
    expect(tools.value[1].legend).toBe('Next appointment: tomorrow 10:00');
  });

  it('keeps new English and Spanish keys in parity', () => {
    expect(Object.keys(en.CONVERSATION_SIDEBAR.TOOLS)).toEqual(
      Object.keys(es.CONVERSATION_SIDEBAR.TOOLS)
    );
    expect(Object.keys(en.CONVERSATION_SIDEBAR.RESPONDER)).toEqual(
      Object.keys(es.CONVERSATION_SIDEBAR.RESPONDER)
    );
    start();
  });
});
