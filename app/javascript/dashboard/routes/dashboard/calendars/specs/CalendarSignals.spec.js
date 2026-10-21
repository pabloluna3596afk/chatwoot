import CalendarAPI from 'dashboard/api/integrations/calendar';
import SearchAPI from 'dashboard/api/search';

it('passes calendar and search cancellation signals to axios without changing request params', async () => {
  const signal = new AbortController().signal;
  const get = vi.fn().mockResolvedValue({ data: {} });
  const post = vi.fn().mockResolvedValue({ data: {} });
  vi.stubGlobal('axios', { get, post });
  try {
    await CalendarAPI.getConnections({ signal });
    expect(get).toHaveBeenLastCalledWith(
      expect.stringContaining('calendar_connections'),
      { signal }
    );
    await CalendarAPI.getCalendars(2, { signal, all: true });
    expect(get).toHaveBeenLastCalledWith(
      expect.stringContaining('/2/calendars'),
      { signal, params: { all: true } }
    );
    await CalendarAPI.getEvents({
      connectionId: 2,
      calendarId: 'shared',
      timeMin: 'start',
      timeMax: 'end',
      signal,
    });
    expect(get).toHaveBeenLastCalledWith(expect.stringContaining('/events'), {
      signal,
      params: {
        connection_id: 2,
        calendar_id: 'shared',
        time_min: 'start',
        time_max: 'end',
      },
    });
    await CalendarAPI.getConversationEvents(9, { signal });
    expect(get).toHaveBeenLastCalledWith(
      expect.stringContaining('/conversations/9/calendar_events'),
      { signal }
    );
    await CalendarAPI.getInvitation({ signal });
    expect(get).toHaveBeenLastCalledWith(
      expect.stringContaining('/invitation'),
      { signal }
    );
    await SearchAPI.conversations({ q: 'Alice' }, { signal });
    expect(get).toHaveBeenLastCalledWith(
      expect.stringContaining('/search/conversations'),
      {
        signal,
        params: { q: 'Alice', page: 1, since: undefined, until: undefined },
      }
    );
    await CalendarAPI.lockEvent('owner', { connection_id: 2 }, { signal });
    expect(post).toHaveBeenLastCalledWith(
      expect.stringContaining('/events/owner/lock'),
      { connection_id: 2 },
      { signal }
    );
  } finally {
    vi.unstubAllGlobals();
  }
});
