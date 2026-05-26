/* Facteur Landing — Checkout Premium MVP
 *
 * Flow : email saisi → POST /api/checkout/start-passwordless →
 *        redirection vers l'URL RevenueCat Web Billing retournée.
 * Identité unique = user_id Supabase, propagé à RevenueCat comme app_user_id
 * pour que l'entitlement Premium suive le compte au login app mobile.
 */
(function () {
    'use strict';

    var API_URL = 'https://facteur-production.up.railway.app';

    var urlParams = new URLSearchParams(window.location.search);
    var utmData = {
        utm_source: urlParams.get('utm_source') || null,
        utm_medium: urlParams.get('utm_medium') || null,
        utm_campaign: urlParams.get('utm_campaign') || null,
    };

    document.querySelectorAll('.checkout-form').forEach(function (form) {
        form.addEventListener('submit', function (e) {
            e.preventDefault();

            var input = form.querySelector('.checkout-form__input');
            var btn = form.querySelector('.checkout-form__btn');
            var errorEl = form.querySelector('.checkout-form__error');
            var offering = form.getAttribute('data-offering') || 'default';
            var email = (input.value || '').trim();

            if (!email) return;

            btn.disabled = true;
            var originalLabel = btn.textContent;
            btn.textContent = '...';
            if (errorEl) errorEl.hidden = true;

            var payload = { email: email, offering: offering };
            if (utmData.utm_source) payload.utm_source = utmData.utm_source;
            if (utmData.utm_medium) payload.utm_medium = utmData.utm_medium;
            if (utmData.utm_campaign) payload.utm_campaign = utmData.utm_campaign;

            fetch(API_URL + '/api/checkout/start-passwordless', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            })
                .then(function (res) {
                    if (!res.ok) {
                        return res.json().then(function (data) {
                            throw new Error(data.detail || 'Erreur');
                        });
                    }
                    return res.json();
                })
                .then(function (data) {
                    if (data && data.checkout_url) {
                        window.location.href = data.checkout_url;
                    } else {
                        throw new Error('Réponse invalide');
                    }
                })
                .catch(function (err) {
                    if (errorEl) {
                        errorEl.textContent =
                            'Impossible de démarrer le paiement. Réessaie ?';
                        errorEl.hidden = false;
                    }
                    btn.textContent = originalLabel;
                    btn.disabled = false;
                    if (window.console) console.warn('checkout failed', err);
                });
        });
    });
})();
