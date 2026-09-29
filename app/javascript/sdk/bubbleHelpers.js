import { addClasses, removeClasses, toggleClass } from './DOMHelpers';
import { IFrameHelper } from './IFrameHelper';
import { isExpandedView } from './settingsHelper';
import {
  CHATWOOT_CLOSED,
  CHATWOOT_OPENED,
} from '../widget/constants/sdkEvents';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';

export const bubbleSVG =
  'M59.96 30.06C51.82 30.74 43.96 32.62 36.06 34.46C28.79 37.23 21.71 40.24 16.08 46.53C5.36 59.33 5.18 75 4.63 90.89C4 111.17 5.25 129.31 7.51 148.96C8.11 157.4 9.81 165.7 11.3 174C13.13 181.44 16.27 188.67 22.24 194.6C28.17 200.49 35.34 203.6 42.73 205.39C49.7 207.07 57.65 207.92 66.97 208.94C98.33 213.17 129.83 211.81 161.21 208.99L161.26 208.99L161.73 208.94C172.23 207.27 182.21 206.32 192.4 205.86C196 206.33 200.39 207.14 204.62 207.99C213.08 209.69 220.81 211.59 220.81 211.59L236 215.38L228.81 201.46C228.81 201.46 225.61 195.25 222.65 188.3C221.17 184.82 219.78 181.13 218.91 178.22C217.32 168.99 220.67 159.08 222.04 148.78C224.9 129.34 226.16 109.79 226.49 90.18C226.56 74.09 226.73 59.42 216.07 47.1C210.4 40.55 203.26 36.77 195.72 34.56C188.72 32.5 180.85 31.44 171.77 30.15L171.2 30.11C132.34 24.62 96.92 27.01 59.96 30.06ZM100.91 78.63C94.48 78.63 89.26 83.89 89.26 90.32L89.26 113.23C89.26 119.66 94.48 124.87 100.91 124.87C107.34 124.87 112.6 119.66 112.6 113.23L112.6 90.32C112.6 83.89 107.34 78.63 100.91 78.63ZM69.24 78.63C62.81 78.63 57.55 83.89 57.55 90.32L57.55 113.23C57.55 119.66 62.81 124.87 69.24 124.87C75.67 124.87 80.88 119.66 80.88 113.23L80.88 90.32C80.88 83.89 75.67 78.63 69.24 78.63Z';

export const body = document.getElementsByTagName('body')[0];
export const widgetHolder = document.createElement('div');

export const bubbleHolder = document.createElement('div');
export const chatBubble = document.createElement('button');
export const closeBubble = document.createElement('button');
export const notificationBubble = document.createElement('span');

export const setBubbleText = bubbleText => {
  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.getElementById('woot-widget--expanded__text');
    textNode.innerText = bubbleText;
  }
};

export const createBubbleIcon = ({ className, path, target }) => {
  let bubbleClassName = `${className} woot-elements--${window.$chatwoot.position}`;
  const bubbleIcon = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'svg'
  );
  bubbleIcon.setAttributeNS(null, 'id', 'woot-widget-bubble-icon');
  bubbleIcon.setAttributeNS(null, 'width', '24');
  bubbleIcon.setAttributeNS(null, 'height', '24');
  bubbleIcon.setAttributeNS(null, 'viewBox', '0 0 240 240');
  bubbleIcon.setAttributeNS(null, 'fill', 'none');
  bubbleIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

  const bubblePath = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'path'
  );
  bubblePath.setAttributeNS(null, 'd', path);
  bubblePath.setAttributeNS(null, 'fill', '#FFFFFF');
  bubblePath.setAttributeNS(null, 'fill-rule', 'evenodd');

  bubbleIcon.appendChild(bubblePath);
  target.appendChild(bubbleIcon);

  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.createElement('div');
    textNode.id = 'woot-widget--expanded__text';
    textNode.innerText = '';
    target.appendChild(textNode);
    bubbleClassName += ' woot-widget--expanded';
  }

  target.className = bubbleClassName;
  target.title = 'Open chat window';
  return target;
};

export const createBubbleHolder = hideMessageBubble => {
  if (hideMessageBubble) {
    addClasses(bubbleHolder, 'woot-hidden');
  }
  addClasses(bubbleHolder, 'woot--bubble-holder');
  bubbleHolder.id = 'cw-bubble-holder';
  bubbleHolder.dataset.turboPermanent = true;
  body.appendChild(bubbleHolder);
};

const handleBubbleToggle = newIsOpen => {
  IFrameHelper.events.onBubbleToggle(newIsOpen);

  if (newIsOpen) {
    dispatchWindowEvent({ eventName: CHATWOOT_OPENED });
  } else {
    dispatchWindowEvent({ eventName: CHATWOOT_CLOSED });
    chatBubble.focus();
  }
};

export const onBubbleClick = (props = {}) => {
  const { toggleValue } = props;
  const { isOpen } = window.$chatwoot;
  if (isOpen === toggleValue) return;

  const newIsOpen = toggleValue === undefined ? !isOpen : toggleValue;
  window.$chatwoot.isOpen = newIsOpen;

  toggleClass(chatBubble, 'woot--hide');
  toggleClass(closeBubble, 'woot--hide');
  toggleClass(widgetHolder, 'woot--hide');

  handleBubbleToggle(newIsOpen);
};

export const onClickChatBubble = () => {
  bubbleHolder.addEventListener('click', onBubbleClick);
};

export const addUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  addClasses(holderEl, 'has-unread-view');
};

export const removeUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  removeClasses(holderEl, 'has-unread-view');
};
