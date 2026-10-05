/* global axios */

import ApiClient from '../ApiClient';

class CalendarAPI extends ApiClient {
  constructor() {
    super('integrations/calendar_connections', { accountScoped: true });
  }

  getConnections() {
    return axios.get(this.url);
  }

  startOAuth() {
    return axios.get(`${this.url}/oauth`);
  }

  disconnect(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  getCalendars(connectionId, { all = false } = {}) {
    return axios.get(`${this.url}/${connectionId}/calendars`, {
      params: all ? { all: true } : {},
    });
  }

  updateCalendars(connectionId, calendars) {
    return axios.patch(`${this.url}/${connectionId}/calendars`, { calendars });
  }

  getEvents({ connectionId, calendarId, timeMin, timeMax }) {
    return axios.get(`${this.url}/events`, {
      params: {
        connection_id: connectionId,
        calendar_id: calendarId,
        time_min: timeMin,
        time_max: timeMax,
      },
    });
  }

  // The text of the invitation of an appointment (account-wide): { template, location, default_template, tokens, max_length }.
  getInvitation() {
    return axios.get(`${this.url}/invitation`);
  }

  updateInvitation({ template, location }) {
    return axios.patch(`${this.url}/invitation`, { template, location });
  }

  createEvent(payload) {
    return axios.post(`${this.url}/events`, payload);
  }

  updateEvent(eventId, payload) {
    return axios.patch(
      `${this.url}/events/${encodeURIComponent(eventId)}`,
      payload
    );
  }

  deleteEvent(eventId, payload) {
    return axios.delete(`${this.url}/events/${encodeURIComponent(eventId)}`, {
      data: payload,
    });
  }

  lockEvent(eventId, payload) {
    return axios.post(
      `${this.url}/events/${encodeURIComponent(eventId)}/lock`,
      payload
    );
  }

  unlockEvent(eventId, payload) {
    return axios.delete(
      `${this.url}/events/${encodeURIComponent(eventId)}/lock`,
      { data: payload }
    );
  }

  // The upcoming appointments of a contact, across all its conversations.
  getContactEvents(contactId) {
    return axios.get(
      `${this.apiVersion}/accounts/${this.accountIdFromRoute}/contacts/${contactId}/calendar_events`
    );
  }

  getConversationEvents(conversationId) {
    return axios.get(
      `${this.apiVersion}/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/calendar_events`
    );
  }
}

export default new CalendarAPI();
