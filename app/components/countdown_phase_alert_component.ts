import type { CountdownElement } from '@18f/identity-countdown/countdown-element';

type Phase = { at_s: number; classes: string; label: string };

export class CountdownPhaseAlertElement extends HTMLElement {
  #countdownEl?: CountdownElement;
  #alertEl?: HTMLElement | null;
  #labelEl?: HTMLElement | null;
  #srPhaseEl?: HTMLElement | null;
  #srExpiryEl?: HTMLElement | null;

  #currentPhaseKey?: string;
  #phases: Phase[] = [];
  #phaseIdx = 0;

  connectedCallback() {
    this.#ensureFallbackLiveRegions();

    this.#labelEl = this.querySelector('[data-role="phase-label"]');
    this.#srPhaseEl = this.srPhaseRegion;
    this.#srExpiryEl = this.srExpiryRegion;

    this.#phases = this.#setupPhases();
    this.#phaseIdx = Math.max(0, this.#phases.length - 1);

    this.#countdownEl = this.querySelector('lg-countdown') || undefined;
    this.#alertEl = this.querySelector('.usa-alert');

    this.addEventListener('lg:countdown:tick', this.#onTick);
  }

  disconnectedCallback() {
    this.removeEventListener('lg:countdown:tick', this.#onTick);
    this.#countdownEl = undefined;
    this.#alertEl = null;
    this.#labelEl = null;
    this.#srPhaseEl = null;
    this.#srExpiryEl = null;
  }

  #setupPhases(): Phase[] {
    try {
      return JSON.parse(this.dataset.phases || '[]') as Phase[];
    } catch {
      return [];
    }
  }

  get srPhaseRegion(): HTMLElement | null {
    const id = this.dataset.srPhaseRegionId || '';

    return id ? document.getElementById(id) : null;
  }
  get srExpiryRegion(): HTMLElement | null {
    const id = this.dataset.srExpiryRegionId || '';

    return id ? document.getElementById(id) : null;
  }
  get baseClasses(): string {
    return (this.dataset.baseClasses || '').trim();
  }

  #ensureFallbackLiveRegions() {
    if (!this.srPhaseRegion) {
      const n = document.createElement('div');
      n.className = 'usa-sr-only';
      n.setAttribute('aria-live', 'polite');
      n.setAttribute('aria-atomic', 'true');
      n.id = 'otp-live-phase-fallback';
      document.body.appendChild(n);
      this.dataset.srPhaseRegionId = n.id;
    }
    if (!this.srExpiryRegion) {
      const n = document.createElement('div');
      n.className = 'usa-sr-only';
      n.setAttribute('role', 'alert');
      n.setAttribute('aria-atomic', 'true');
      n.id = 'otp-live-expiry-fallback';
      document.body.appendChild(n);
      this.dataset.srExpiryRegionId = n.id;
    }
  }

  #remaining(): number | null {
    const ms = this.#countdownEl?.timeRemaining;

    if (typeof ms === 'number' && !Number.isNaN(ms)) {
      return Math.max(0, Math.ceil(ms / 1000));
    }
    return null;
  }

  #applyPhase(active: Phase) {
    const key = String(active.at_s);

    if (this.#currentPhaseKey === key) {
      return;
    }

    this.#updateLabel(active.label);
    this.#updateAlertClasses(active.classes);
    this.#announceToScreenReaders(active);

    this.#currentPhaseKey = key;
  }

  #updateLabel(label: string) {
    if (this.#labelEl) {
      this.#labelEl.innerHTML = this.#sanitizeHtml(label);
    }
  }

  /**
   * Sanitizes HTML content by only allowing safe tags (strong, em, b, i, span).
   * This prevents XSS attacks while preserving necessary formatting.
   */
  #sanitizeHtml(html: string): string {
    const template = document.createElement('template');
    template.innerHTML = html;
    const fragment = template.content;

    const allowedTags = new Set(['STRONG', 'EM', 'B', 'I', 'SPAN', '#text']);

    const sanitizeNode = (node: Node): Node | null => {
      if (node.nodeType === Node.TEXT_NODE) {
        return node.cloneNode(true);
      }

      if (node.nodeType === Node.ELEMENT_NODE) {
        const element = node as Element;
        if (!allowedTags.has(element.tagName)) {
          // Replace disallowed elements with their text content
          return document.createTextNode(element.textContent || '');
        }

        // Clone the allowed element without attributes (except for span class)
        const clone = document.createElement(element.tagName.toLowerCase());
        // Recursively sanitize children
        Array.from(node.childNodes).forEach((child) => {
          const sanitizedChild = sanitizeNode(child);
          if (sanitizedChild) {
            clone.appendChild(sanitizedChild);
          }
        });
        return clone;
      }

      return null;
    };

    const sanitizedFragment = document.createDocumentFragment();
    Array.from(fragment.childNodes).forEach((child) => {
      const sanitizedChild = sanitizeNode(child);
      if (sanitizedChild) {
        sanitizedFragment.appendChild(sanitizedChild);
      }
    });

    const wrapper = document.createElement('div');
    wrapper.appendChild(sanitizedFragment);
    return wrapper.innerHTML;
  }

  #updateAlertClasses(classes: string) {
    const alert = this.#alertEl ?? this.querySelector('.usa-alert');

    if (alert) {
      alert.className = this.#joinClasses(this.baseClasses, classes);
    }
  }

  #joinClasses(...parts: string[]) {
    return parts.join(' ').replace(/\s+/g, ' ').trim();
  }

  #htmlToText(html: string): string {
    const div = document.createElement('div');

    div.innerHTML = html;
    return (div.textContent || '').replace(/\s+/g, ' ').trim();
  }

  #announceToScreenReaders(active: Phase) {
    const text = this.#htmlToText(active.label);

    if (active.at_s > 0) {
      this.#srPhaseEl && (this.#srPhaseEl.textContent = text);
    } else {
      this.#srExpiryEl && (this.#srExpiryEl.textContent = text);
      this.#srPhaseEl && (this.#srPhaseEl.textContent = '');
    }
  }

  #onTick = () => {
    const remainingS = this.#remaining();

    if (remainingS === null || this.#phases.length === 0) {
      return;
    }

    while (this.#phaseIdx > 0 && remainingS <= this.#phases[this.#phaseIdx - 1].at_s) {
      this.#phaseIdx--;
    }

    this.#applyPhase(this.#phases[this.#phaseIdx]);
  };
}

declare global {
  interface HTMLElementTagNameMap {
    'lg-countdown-phase-alert': CountdownPhaseAlertElement;
  }
}

if (!customElements.get('lg-countdown-phase-alert')) {
  customElements.define('lg-countdown-phase-alert', CountdownPhaseAlertElement);
}
