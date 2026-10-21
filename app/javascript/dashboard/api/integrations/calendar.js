/* global axios */

import ApiClient from '../ApiClient';

class CalendarAPI extends ApiClient {
  constructor() {
    super('integrations/calendar_connections', { accountScoped: true });
  }

  getConnections({ signal } = {}) {
    return axios.get(this.url, { signal });
  }

  startOAuth() {
    return axios.get(`${this.url}/oauth`);
  }

  disconnect(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  getCalendars(connectionId, { all = false, signal } = {}) {
    return axios.get(`${this.url}/${connectionId}/calendars`, {
      params: all ? { all: true } : {},
      signal,
    });
  }

  updateCalendars(connectionId, calendars) {
    return axios.patch(`${this.url}/${connectionId}/calendars`, { calendars });
  }

  getEvents({ connectionId, calendarId, timeMin, timeMax, signal }) {
    return axios.get(`${this.url}/events`, {
      signal,
      params: {
        connection_id: connectionId,
        calendar_id: calendarId,
        time_min: timeMin,
        time_max: timeMax,
      },
    });
  }

  // The text of the invitation of an appointment (account-wide): { template, location, default_template, tokens, max_length }.
  getInvitation({ signal } = {}) {
    return axios.get(`${this.url}/invitation`, { signal });
  }

  updateInvitation({ template, location }) {
    return axios.patch(`${this.url}/invitation`, { template, location });
  }

  getAppointmentAttributes() {
    return axios.get(`${this.url}/appointment_attributes`);
  }

  updateAppointmentAttributes(keys) {
    return axios.patch(`${this.url}/appointment_attributes`, { keys });
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

  lockEvent(eventId, payload, { signal } = {}) {
    return axios.post(
      `${this.url}/events/${encodeURIComponent(eventId)}/lock`,
      payload,
      { signal }
    );
  }

  unlockEvent(eventId, payload) {
    return axios.delete(
      `${this.url}/events/${encodeURIComponent(eventId)}/lock`,
      { data: payload }
    );
  }

  // The upcoming appointments of a contact, across all its conversations.
  getContactEvents(contactId, { signal } = {}) {
    return axios.get(
      `${this.apiVersion}/accounts/${this.accountIdFromRoute}/contacts/${contactId}/calendar_events`,
      { signal }
    );
  }

  getConversationEvents(conversationId, { signal } = {}) {
    return axios.get(
      `${this.apiVersion}/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/calendar_events`,
      { signal }
    );
  }
}

export default new CalendarAPI();
